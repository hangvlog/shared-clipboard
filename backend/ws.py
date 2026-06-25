"""
Socket.IO 事件路由

处理桌面端与移动端之间的实时同步消息。
"""
import logging
import uuid
from datetime import datetime
from typing import Optional

from src.ws.hub import sio, manager
from src.database import db_manager, User
from src.models.sync import DeviceConnection, SyncSession, SyncMessage
from src.auth import decode_token

logger = logging.getLogger(__name__)


# ============================================
# 连接生命周期事件
# ============================================

@sio.event
async def connect(sid, environ):
    """客户端连接"""
    logger.info("客户端连接: %s", sid)
    # 连接时只记录，设备注册在 register_device 事件中完成


@sio.event
async def disconnect(sid):
    """客户端断开连接"""
    # 获取设备信息
    device_info = manager.get_device_info(sid)
    device_id = device_info.get('device_id') if device_info else None

    # 更新数据库中的连接状态
    if device_id:
        try:
            with db_manager.session_scope() as db:
                device = db.query(DeviceConnection).filter(
                    DeviceConnection.device_id == device_id
                ).first()
                if device:
                    device.is_online = False
                    device.last_seen = datetime.utcnow()
                    device.socket_id = None
        except Exception as e:
            logger.error(f"更新设备离线状态失败: {e}")

    # 清理内存中的连接
    await manager.disconnect(sid)
    logger.info(f"客户端断开: {sid}")


# ============================================
# 设备管理事件
# ============================================

@sio.event
async def register_device(sid, data):
    """
    设备注册

    请求数据:
        deviceId: str - 设备唯一标识
        deviceType: str - 设备类型 ('desktop' | 'mobile')
        deviceName: str - 设备名称（可选）
        platform: str - 操作系统（可选）
        appVersion: str - 应用版本（可选）
        pairedDesktopId: str - 配对的桌面端ID（移动端可选）
        token: str - JWT Token（可选，用于关联用户）

    返回:
        success: bool
        deviceId: str
        message: str
    """
    logger.info("设备注册请求: sid=%s, data=%s", sid, data)
    device_id = data.get('deviceId')
    device_type = data.get('deviceType')
    device_name = data.get('deviceName', '')
    platform = data.get('platform')
    app_version = data.get('appVersion')
    paired_desktop_id = data.get('pairedDesktopId')
    token = data.get('token')

    if not device_id or not device_type:
        return {'success': False, 'message': 'deviceId 和 deviceType 是必需的'}

    if device_type not in ('desktop', 'mobile'):
        return {'success': False, 'message': 'deviceType 必须是 desktop 或 mobile'}

    # 验证 Token 并获取用户ID
    user_id = None
    if token:
        payload = decode_token(token)
        if payload:
            username = payload.get("sub")
            if username:
                try:
                    with db_manager.session_scope() as db:
                        user = db.query(User).filter(User.username == username).first()
                        if user:
                            user_id = user.id
                            logger.info(f"设备 {device_id} 关联用户: {username} (ID: {user_id})")
                except Exception as e:
                    logger.warning(f"查询用户失败: {e}")

    # 注册到内存管理器
    await manager.connect(sid, device_id, device_type, device_name, user_id)

    # 更新数据库
    try:
        with db_manager.session_scope() as db:
            device = db.query(DeviceConnection).filter(
                DeviceConnection.device_id == device_id
            ).first()

            if device:
                # 更新现有设备
                device.device_type = device_type
                device.device_name = device_name
                device.is_online = True
                device.last_seen = datetime.utcnow()
                device.socket_id = sid
                if platform:
                    device.platform = platform
                if app_version:
                    device.app_version = app_version
                if paired_desktop_id:
                    device.paired_desktop_id = paired_desktop_id
                if user_id:
                    device.user_id = user_id
            else:
                # 创建新设备
                device = DeviceConnection(
                    device_id=device_id,
                    device_type=device_type,
                    device_name=device_name,
                    is_online=True,
                    last_seen=datetime.utcnow(),
                    socket_id=sid,
                    platform=platform,
                    app_version=app_version,
                    paired_desktop_id=paired_desktop_id,
                    user_id=user_id,
                )
                db.add(device)

        logger.info(f"设备注册成功: {device_id} ({device_type})" + (f" 用户ID: {user_id}" if user_id else ""))
        return {'success': True, 'deviceId': device_id, 'message': '注册成功'}

    except Exception as e:
        logger.error(f"设备注册失败: {e}")
        return {'success': False, 'message': f'注册失败: {str(e)}'}


@sio.event
async def get_online_devices(sid, data):
    """
    获取在线设备列表

    返回:
        success: bool
        devices: list
    """
    devices = manager.get_online_devices()
    logger.info("WS [get_online_devices] sid=%s - 在线设备数: %d", sid, len(devices))
    return {'success': True, 'devices': devices}


# ============================================
# 会话管理事件
# ============================================

@sio.event
async def join_session(sid, data):
    """
    加入会话房间（带用户权限验证）

    请求数据:
        sessionId: str - 会话ID

    返回:
        success: bool
        sessionId: str
        devices: list - 会话中的其他设备
    """
    session_id = data.get('sessionId')
    logger.info("WS [join_session] sid=%s - 输入: %s", sid, data)
    if not session_id:
        return {'success': False, 'message': 'sessionId 是必需的'}

    # 获取当前用户信息
    device_info = manager.get_device_info(sid)
    current_user_id = device_info.get('user_id') if device_info else None

    # 验证用户权限：检查会话是否属于当前用户
    try:
        with db_manager.session_scope() as db:
            session = db.query(SyncSession).filter(SyncSession.session_id == session_id).first()
            if session:
                # 如果会话有所有者，验证权限
                if session.owner_user_id is not None:
                    if current_user_id is None:
                        return {'success': False, 'message': '需要登录才能加入此会话'}
                    if session.owner_user_id != current_user_id:
                        logger.warning(f"用户 {current_user_id} 尝试加入不属于自己的会话 {session_id} (owner: {session.owner_user_id})")
                        return {'success': False, 'message': '无权访问此会话'}
            else:
                return {'success': False, 'message': '会话不存在'}
    except Exception as e:
        logger.error(f"验证会话权限失败: {e}")
        return {'success': False, 'message': '验证权限失败'}

    await manager.join_session(sid, session_id)

    # 获取会话中的其他设备（只返回同一用户的设备）
    devices = manager.get_session_devices(session_id)
    if current_user_id:
        # 过滤只保留同一用户的设备
        devices = [d for d in devices if manager.connections.get(
            manager.devices.get(d['deviceId'])
        ) and manager.connections.get(
            manager.devices.get(d['deviceId'])
        ).get('user_id') == current_user_id]

    # 通知会话中同一用户的其他设备有新成员加入
    if device_info and current_user_id:
        await manager.broadcast_to_session_for_user(session_id, current_user_id, 'device_joined', {
            'sessionId': session_id,
            'device': {
                'deviceId': device_info.get('device_id'),
                'deviceType': device_info.get('device_type'),
                'deviceName': device_info.get('device_name'),
            }
        }, skip_sid=sid)

    return {'success': True, 'sessionId': session_id, 'devices': devices}


@sio.event
async def leave_session(sid, data):
    """
    离开会话房间（带用户级别隔离）

    请求数据:
        sessionId: str - 会话ID
    """
    session_id = data.get('sessionId')
    logger.info("WS [leave_session] sid=%s - 输入: %s", sid, data)
    if not session_id:
        return {'success': False, 'message': 'sessionId 是必需的'}

    # 通知同一用户的其他设备
    device_info = manager.get_device_info(sid)
    if device_info:
        user_id = device_info.get('user_id')
        leave_data = {
            'sessionId': session_id,
            'deviceId': device_info.get('device_id'),
        }
        if user_id:
            await manager.broadcast_to_session_for_user(session_id, user_id, 'device_left', leave_data, skip_sid=sid)
        else:
            await manager.broadcast_to_session(session_id, 'device_left', leave_data, skip_sid=sid)

    await manager.leave_session(sid, session_id)
    return {'success': True}


@sio.event
async def create_session(sid, data):
    """
    创建新会话（桌面端）

    请求数据:
        title: str - 会话标题（可选）
        currentDirectory: str - 当前工作目录（可选）

    返回:
        success: bool
        sessionId: str
    """
    device_info = manager.get_device_info(sid)
    if not device_info:
        return {'success': False, 'message': '设备未注册'}

    # 允许任何已登录用户创建会话（不再限制只有桌面端）
    if not device_info.get('user_id'):
        return {'success': False, 'message': '请先登录后再创建会话'}

    device_id = device_info.get('device_id')
    user_id = device_info.get('user_id')  # 获取用户ID作为会话所有者
    title = data.get('title', '新会话')
    current_directory = data.get('currentDirectory', '')

    # 生成会话ID
    session_id = str(uuid.uuid4())

    try:
        with db_manager.session_scope() as db:
            session = SyncSession(
                session_id=session_id,
                desktop_device_id=device_id,
                owner_user_id=user_id,  # 记录会话所有者
                title=title,
                current_directory=current_directory,
                status='idle',
            )
            db.add(session)

        # 自动加入会话
        await manager.join_session(sid, session_id)

        logger.info(f"会话创建成功: {session_id}, owner_user_id: {user_id}")
        return {'success': True, 'sessionId': session_id}

    except Exception as e:
        logger.error(f"创建会话失败: {e}")
        return {'success': False, 'message': f'创建失败: {str(e)}'}


@sio.event
async def sync_local_sessions(sid, data):
    """
    同步桌面端本地会话到后端（桌面端登录后调用）

    请求数据:
        sessions: list - 本地会话列表
            - localSessionId: str - 本地会话路径/ID
            - title: str - 会话标题
            - currentDirectory: str - 工作目录
            - messageCount: int - 消息数量
            - updatedAt: str - 最后更新时间

    返回:
        success: bool
        syncedCount: int - 同步的会话数量
    """
    device_info = manager.get_device_info(sid)
    if not device_info:
        return {'success': False, 'message': '设备未注册'}

    if device_info.get('device_type') != 'desktop':
        return {'success': False, 'message': '只有桌面端可以同步本地会话'}

    user_id = device_info.get('user_id')
    if not user_id:
        return {'success': False, 'message': '请先登录'}

    device_id = device_info.get('device_id')
    sessions = data.get('sessions', [])

    if not sessions:
        return {'success': True, 'syncedCount': 0}

    synced_count = 0
    try:
        with db_manager.session_scope() as db:
            for sess in sessions:
                local_id = sess.get('localSessionId', '')
                title = sess.get('title', '未命名会话')
                current_dir = sess.get('currentDirectory', '')
                message_count = sess.get('messageCount', 0)

                # 检查是否已存在（通过 local_session_id 和 user_id）
                existing = db.query(SyncSession).filter(
                    SyncSession.owner_user_id == user_id,
                    SyncSession.local_session_id == local_id
                ).first()

                if existing:
                    # 更新现有会话
                    existing.title = title
                    existing.current_directory = current_dir
                    existing.message_count = message_count
                    existing.desktop_device_id = device_id
                else:
                    # 创建新会话
                    new_session = SyncSession(
                        session_id=str(uuid.uuid4()),
                        desktop_device_id=device_id,
                        owner_user_id=user_id,
                        local_session_id=local_id,
                        title=title,
                        current_directory=current_dir,
                        message_count=message_count,
                        status='idle',
                    )
                    db.add(new_session)
                synced_count += 1

        logger.info(f"同步本地会话成功: {synced_count} 个, user_id: {user_id}")
        return {'success': True, 'syncedCount': synced_count}

    except Exception as e:
        logger.error(f"同步本地会话失败: {e}")
        return {'success': False, 'message': str(e)}


@sio.event
async def get_sessions(sid, data):
    """
    获取会话列表（只返回当前用户的会话）

    请求数据:
        desktopDeviceId: str - 桌面端设备ID（可选）

    返回:
        success: bool
        sessions: list
    """
    desktop_device_id = data.get('desktopDeviceId')

    # 获取当前用户ID
    device_info = manager.get_device_info(sid)
    current_user_id = device_info.get('user_id') if device_info else None

    try:
        with db_manager.session_scope() as db:
            query = db.query(SyncSession)

            # 只返回当前用户的会话（用户级别隔离）
            if current_user_id:
                query = query.filter(SyncSession.owner_user_id == current_user_id)
            else:
                # 未登录用户只能看到无主会话
                query = query.filter(SyncSession.owner_user_id == None)

            if desktop_device_id:
                query = query.filter(SyncSession.desktop_device_id == desktop_device_id)

            sessions = query.order_by(SyncSession.updated_at.desc()).limit(50).all()

            result = [{
                'sessionId': s.session_id,
                'title': s.title,
                'currentDirectory': s.current_directory,
                'status': s.status,
                'messageCount': s.message_count,
                'lastMessageAt': s.last_message_at.isoformat() if s.last_message_at else None,
                'createdAt': s.created_at.isoformat() if s.created_at else None,
            } for s in sessions]

        return {'success': True, 'sessions': result}

    except Exception as e:
        logger.error(f"获取会话列表失败: {e}")
        return {'success': False, 'message': str(e)}


# ============================================
# 消息同步事件
# ============================================

@sio.event
async def mobile_send_message(sid, data):
    """
    移动端发送消息 -> 转发到桌面端（带用户级别隔离）

    请求数据:
        sessionId: str - 会话ID
        message: str - 消息内容
        messageId: str - 消息ID（可选，不传则自动生成）
    """
    session_id = data.get('sessionId')
    message = data.get('message')
    message_id = data.get('messageId', str(uuid.uuid4()))
    logger.info("WS [mobile_send_message] sid=%s - 会话: %s, 消息ID: %s, 内容长度: %d",
                sid, session_id, message_id, len(message or ''))

    if not session_id or not message:
        return {'success': False, 'message': '缺少必需参数'}

    device_info = manager.get_device_info(sid)
    device_id = device_info.get('device_id') if device_info else None
    user_id = device_info.get('user_id') if device_info else None

    # 验证用户权限
    if not user_id:
        return {'success': False, 'message': '需要登录才能发送消息'}

    # 验证会话归属
    try:
        with db_manager.session_scope() as db:
            session = db.query(SyncSession).filter(SyncSession.session_id == session_id).first()
            if not session:
                return {'success': False, 'message': '会话不存在'}
            if session.owner_user_id and session.owner_user_id != user_id:
                logger.warning(f"用户 {user_id} 尝试向不属于自己的会话 {session_id} 发送消息")
                return {'success': False, 'message': '无权向此会话发送消息'}
    except Exception as e:
        logger.error(f"验证会话权限失败: {e}")
        return {'success': False, 'message': '验证权限失败'}

    # 保存消息到数据库
    try:
        with db_manager.session_scope() as db:
            sync_message = SyncMessage(
                message_id=message_id,
                session_id=session_id,
                role='user',
                content=message,
                timestamp=datetime.utcnow(),
                source_device_id=device_id,
                source_device_type='mobile',
            )
            db.add(sync_message)

            # 更新会话统计
            session = db.query(SyncSession).filter(SyncSession.session_id == session_id).first()
            if session:
                session.message_count = (session.message_count or 0) + 1
                session.last_message_at = datetime.utcnow()

    except Exception as e:
        logger.error(f"保存消息失败: {e}")

    # 构造消息数据
    message_data = {
        'sessionId': session_id,
        'messageId': message_id,
        'message': message,
        'from': 'mobile',
        'fromDevice': device_id,
        'timestamp': datetime.utcnow().isoformat(),
    }

    # 只发送给同一用户的桌面端（用户级别隔离）
    await manager.send_to_user_desktops(user_id, 'desktop_receive_message', message_data, skip_sid=sid)
    logger.info(f"消息已发送到用户 {user_id} 的桌面端")

    return {'success': True, 'messageId': message_id}


@sio.event
async def desktop_message_update(sid, data):
    """
    桌面端消息更新 -> 广播到移动端 + 持久化

    请求数据:
        sessionId: str - 会话ID
        messageId: str - 消息ID
        role: str - 角色 ('user' | 'assistant' | 'system')
        content: str - 消息内容
        isStreaming: bool - 是否正在流式输出
        isComplete: bool - 消息是否完成
        thinking: str - 思考过程（可选）
        toolCalls: list - 工具调用（可选）
    """
    session_id = data.get('sessionId')
    message_id = data.get('messageId')
    role = data.get('role', 'assistant')
    content = data.get('content', '')
    is_streaming = data.get('isStreaming', False)
    is_complete = data.get('isComplete', True)
    thinking = data.get('thinking')
    tool_calls = data.get('toolCalls')
    logger.info("WS [desktop_message_update] sid=%s - 会话: %s, 消息ID: %s, 角色: %s, 内容长度: %d, 流式: %s, 完成: %s",
                sid, session_id, message_id, role, len(content), is_streaming, is_complete)

    if not session_id or not message_id:
        return {'success': False, 'message': '缺少必需参数'}

    device_info = manager.get_device_info(sid)
    device_id = device_info.get('device_id') if device_info else None

    # 保存或更新消息到数据库
    try:
        with db_manager.session_scope() as db:
            sync_message = db.query(SyncMessage).filter(
                SyncMessage.message_id == message_id
            ).first()

            if sync_message:
                # 更新现有消息
                sync_message.content = content
                sync_message.is_streaming = is_streaming
                sync_message.is_complete = is_complete
                if thinking:
                    sync_message.thinking = thinking
                if tool_calls:
                    sync_message.set_tool_calls(tool_calls)
            else:
                # 创建新消息
                sync_message = SyncMessage(
                    message_id=message_id,
                    session_id=session_id,
                    role=role,
                    content=content,
                    timestamp=datetime.utcnow(),
                    is_streaming=is_streaming,
                    is_complete=is_complete,
                    thinking=thinking,
                    source_device_id=device_id,
                    source_device_type='desktop',
                )
                if tool_calls:
                    sync_message.set_tool_calls(tool_calls)
                db.add(sync_message)

                # 更新会话统计
                session = db.query(SyncSession).filter(SyncSession.session_id == session_id).first()
                if session:
                    session.message_count = (session.message_count or 0) + 1
                    session.last_message_at = datetime.utcnow()

    except Exception as e:
        logger.error(f"保存消息失败: {e}")

    # 获取用户ID用于隔离广播
    user_id = device_info.get('user_id') if device_info else None

    # 广播到会话中同一用户的所有客户端（除了发送者）
    if user_id:
        await manager.broadcast_to_session_for_user(session_id, user_id, 'message_update', {
            'sessionId': session_id,
            'messageId': message_id,
            'role': role,
            'content': content,
            'isStreaming': is_streaming,
            'isComplete': is_complete,
            'thinking': thinking,
            'toolCalls': tool_calls,
            'timestamp': datetime.utcnow().isoformat(),
        }, skip_sid=sid)
    else:
        # 如果没有用户ID，回退到原有逻辑（但仅限会话内）
        await manager.broadcast_to_session(session_id, 'message_update', {
            'sessionId': session_id,
            'messageId': message_id,
            'role': role,
            'content': content,
            'isStreaming': is_streaming,
            'isComplete': is_complete,
            'thinking': thinking,
            'toolCalls': tool_calls,
            'timestamp': datetime.utcnow().isoformat(),
        }, skip_sid=sid)

    return {'success': True}


@sio.event
async def desktop_stream_chunk(sid, data):
    """
    桌面端流式输出块 -> 广播到移动端（带用户级别隔离）

    请求数据:
        sessionId: str - 会话ID
        messageId: str - 消息ID
        content: str - 累积的内容
        delta: str - 新增的内容（增量）
    """
    session_id = data.get('sessionId')
    message_id = data.get('messageId')
    content = data.get('content', '')
    delta = data.get('delta', '')
    logger.debug("WS [desktop_stream_chunk] sid=%s - 会话: %s, 消息ID: %s, 增量长度: %d",
                 sid, session_id, message_id, len(delta))

    if not session_id:
        return

    device_info = manager.get_device_info(sid)
    user_id = device_info.get('user_id') if device_info else None

    # 广播到会话中同一用户的设备
    stream_data = {
        'sessionId': session_id,
        'messageId': message_id,
        'content': content,
        'delta': delta,
        'isStreaming': True,
        'timestamp': datetime.utcnow().isoformat(),
    }

    if user_id:
        await manager.broadcast_to_session_for_user(session_id, user_id, 'stream_chunk', stream_data, skip_sid=sid)
    else:
        await manager.broadcast_to_session(session_id, 'stream_chunk', stream_data, skip_sid=sid)


@sio.event
async def desktop_status_change(sid, data):
    """
    桌面端状态变化 -> 广播到移动端（带用户级别隔离）

    请求数据:
        sessionId: str - 会话ID
        status: str - 状态
        toolName: str - 当前工具名称（可选）
        extra: dict - 额外信息（可选）
    """
    session_id = data.get('sessionId')
    status = data.get('status')
    logger.info("WS [desktop_status_change] sid=%s - 会话: %s, 状态: %s", sid, session_id, status)

    if not session_id or not status:
        return

    # 更新数据库中的会话状态
    try:
        with db_manager.session_scope() as db:
            session = db.query(SyncSession).filter(SyncSession.session_id == session_id).first()
            if session:
                session.status = status
    except Exception as e:
        logger.error(f"更新会话状态失败: {e}")

    device_info = manager.get_device_info(sid)
    user_id = device_info.get('user_id') if device_info else None

    # 广播状态变化（用户级别隔离）
    status_data = {
        'sessionId': session_id,
        'status': status,
        'toolName': data.get('toolName'),
        'extra': data.get('extra'),
        'timestamp': datetime.utcnow().isoformat(),
    }

    if user_id:
        await manager.broadcast_to_session_for_user(session_id, user_id, 'status_change', status_data, skip_sid=sid)
    else:
        await manager.broadcast_to_session(session_id, 'status_change', status_data, skip_sid=sid)


# ============================================
# 历史同步事件
# ============================================

@sio.event
async def sync_history(sid, data):
    """
    同步历史消息（移动端上线时调用，带用户权限验证）

    请求数据:
        sessionId: str - 会话ID
        since: str - 上次同步时间（ISO格式，可选）
        limit: int - 返回条数限制（默认50）

    返回:
        success: bool
        messages: list
        hasMore: bool
    """
    session_id = data.get('sessionId')
    since_str = data.get('since')
    limit = min(data.get('limit', 50), 100)  # 最多100条
    logger.info("WS [sync_history] sid=%s - 会话: %s, since: %s, limit: %d", sid, session_id, since_str, limit)

    if not session_id:
        return {'success': False, 'message': 'sessionId 是必需的'}

    # 获取当前用户信息并验证权限
    device_info = manager.get_device_info(sid)
    current_user_id = device_info.get('user_id') if device_info else None

    try:
        with db_manager.session_scope() as db:
            # 先验证会话权限
            session = db.query(SyncSession).filter(SyncSession.session_id == session_id).first()
            if not session:
                return {'success': False, 'message': '会话不存在'}

            # 如果会话有所有者，验证权限
            if session.owner_user_id is not None:
                if current_user_id is None:
                    return {'success': False, 'message': '需要登录才能访问此会话'}
                if session.owner_user_id != current_user_id:
                    logger.warning(f"用户 {current_user_id} 尝试同步不属于自己的会话 {session_id} 历史")
                    return {'success': False, 'message': '无权访问此会话'}

            query = db.query(SyncMessage).filter(SyncMessage.session_id == session_id)

            if since_str:
                try:
                    since = datetime.fromisoformat(since_str.replace('Z', '+00:00'))
                    query = query.filter(SyncMessage.timestamp > since)
                except ValueError:
                    pass

            # 按时间倒序获取，然后反转
            messages = query.order_by(SyncMessage.timestamp.desc()).limit(limit + 1).all()
            has_more = len(messages) > limit
            messages = messages[:limit]
            messages.reverse()  # 恢复时间正序

            result = [msg.to_dict() for msg in messages]

        return {'success': True, 'messages': result, 'hasMore': has_more}

    except Exception as e:
        logger.error(f"同步历史消息失败: {e}")
        return {'success': False, 'message': str(e)}


# ============================================
# 权限相关事件
# ============================================

@sio.event
async def desktop_permission_request(sid, data):
    """
    桌面端请求权限确认 -> 通知移动端（带用户级别隔离）

    请求数据:
        sessionId: str - 会话ID
        requestId: str - 请求ID
        tool: str - 工具名称
        input: dict - 工具输入
        description: str - 描述（可选）
    """
    session_id = data.get('sessionId')
    logger.info("WS [desktop_permission_request] sid=%s - 会话: %s, 工具: %s", sid, session_id, data.get('tool'))
    if not session_id:
        return

    device_info = manager.get_device_info(sid)
    user_id = device_info.get('user_id') if device_info else None

    permission_data = {
        'sessionId': session_id,
        'requestId': data.get('requestId'),
        'tool': data.get('tool'),
        'input': data.get('input'),
        'description': data.get('description'),
        'timestamp': datetime.utcnow().isoformat(),
    }

    # 只发送给同一用户的移动端
    if user_id:
        await manager.send_to_user_mobiles(user_id, 'permission_request', permission_data, skip_sid=sid)
    else:
        # 回退到旧逻辑
        await manager.send_to_mobiles_in_session(session_id, 'permission_request', permission_data)


@sio.event
async def mobile_permission_response(sid, data):
    """
    移动端响应权限请求 -> 转发到桌面端（带用户级别隔离）

    请求数据:
        sessionId: str - 会话ID
        requestId: str - 请求ID
        allow: bool - 是否允许
        message: str - 拒绝原因（可选）
    """
    session_id = data.get('sessionId')
    logger.info("WS [mobile_permission_response] sid=%s - 会话: %s, 允许: %s", sid, session_id, data.get('allow'))
    if not session_id:
        return

    device_info = manager.get_device_info(sid)
    user_id = device_info.get('user_id') if device_info else None

    response_data = {
        'sessionId': session_id,
        'requestId': data.get('requestId'),
        'allow': data.get('allow', False),
        'message': data.get('message'),
        'timestamp': datetime.utcnow().isoformat(),
    }

    # 只发送给同一用户的桌面端
    if user_id:
        await manager.send_to_user_desktops(user_id, 'permission_response', response_data, skip_sid=sid)
    else:
        # 回退到旧逻辑
        await manager.send_to_desktops_in_session(session_id, 'permission_response', response_data)


# ============================================
# 统计信息事件
# ============================================

@sio.event
async def get_stats(sid, data):
    """获取连接统计信息"""
    stats = manager.get_stats()
    logger.info("WS [get_stats] sid=%s - 统计: %s", sid, stats)
    return {'success': True, 'stats': stats}


# ============================================
# 浏览器同步事件
# ============================================

@sio.event
async def browser_navigate(sid, data):
    """
    浏览器导航事件 -> 广播到会话

    请求数据:
        sessionId: str - 会话ID
        url: str - 目标URL
        title: str - 页面标题（可选）
    """
    session_id = data.get('sessionId')
    url = data.get('url')
    logger.info("WS [browser_navigate] sid=%s - 会话: %s, URL: %s", sid, session_id, url)

    if not session_id or not url:
        return {'success': False, 'message': '缺少必需参数'}

    # 广播到会话中的所有客户端
    await manager.broadcast_to_session(session_id, 'browser_navigate', {
        'sessionId': session_id,
        'url': url,
        'title': data.get('title', ''),
        'timestamp': datetime.utcnow().isoformat(),
    }, skip_sid=sid)

    return {'success': True}


@sio.event
async def browser_screenshot(sid, data):
    """
    浏览器截图事件 -> 广播到会话

    请求数据:
        sessionId: str - 会话ID
        screenshot: str - Base64编码的截图数据
        url: str - 当前URL（可选）
        width: int - 截图宽度（可选）
        height: int - 截图高度（可选）
    """
    session_id = data.get('sessionId')
    screenshot = data.get('screenshot')
    logger.info("WS [browser_screenshot] sid=%s - 会话: %s, 截图大小: %d字符",
                sid, session_id, len(screenshot or ''))

    if not session_id or not screenshot:
        return {'success': False, 'message': '缺少必需参数'}

    # 广播到会话中的所有客户端
    await manager.broadcast_to_session(session_id, 'browser_screenshot', {
        'sessionId': session_id,
        'screenshot': screenshot,
        'url': data.get('url', ''),
        'width': data.get('width'),
        'height': data.get('height'),
        'timestamp': datetime.utcnow().isoformat(),
    }, skip_sid=sid)

    return {'success': True}


@sio.event
async def browser_status(sid, data):
    """
    浏览器状态变化 -> 广播到会话

    请求数据:
        sessionId: str - 会话ID
        isLoading: bool - 是否正在加载
        url: str - 当前URL
        title: str - 页面标题（可选）
        canGoBack: bool - 是否可以后退（可选）
        canGoForward: bool - 是否可以前进（可选）
    """
    session_id = data.get('sessionId')
    logger.info("WS [browser_status] sid=%s - 会话: %s, 加载中: %s, URL: %s",
                sid, session_id, data.get('isLoading'), data.get('url'))

    if not session_id:
        return {'success': False, 'message': '缺少sessionId'}

    # 广播到会话中的所有客户端
    await manager.broadcast_to_session(session_id, 'browser_status', {
        'sessionId': session_id,
        'isLoading': data.get('isLoading', False),
        'url': data.get('url', ''),
        'title': data.get('title', ''),
        'canGoBack': data.get('canGoBack', False),
        'canGoForward': data.get('canGoForward', False),
        'timestamp': datetime.utcnow().isoformat(),
    }, skip_sid=sid)

    return {'success': True}


@sio.event
async def browser_dom_snapshot(sid, data):
    """
    浏览器DOM快照 -> 广播到会话

    请求数据:
        sessionId: str - 会话ID
        snapshot: str - DOM快照内容（简化的HTML或结构化数据）
        selector: str - 选择器范围（可选，不传则为整个页面）
        url: str - 当前URL（可选）
    """
    session_id = data.get('sessionId')
    snapshot = data.get('snapshot')
    logger.info("WS [browser_dom_snapshot] sid=%s - 会话: %s, 快照大小: %d字符",
                sid, session_id, len(snapshot or ''))

    if not session_id or not snapshot:
        return {'success': False, 'message': '缺少必需参数'}

    # 广播到会话中的所有客户端
    await manager.broadcast_to_session(session_id, 'browser_dom_snapshot', {
        'sessionId': session_id,
        'snapshot': snapshot,
        'selector': data.get('selector'),
        'url': data.get('url', ''),
        'timestamp': datetime.utcnow().isoformat(),
    }, skip_sid=sid)

    return {'success': True}


@sio.event
async def browser_action(sid, data):
    """
    浏览器动作事件 -> 广播到会话（用于同步点击、填充等操作）

    请求数据:
        sessionId: str - 会话ID
        action: str - 动作类型 ('click' | 'fill' | 'scroll' | 'back' | 'forward' | 'reload')
        selector: str - 目标元素选择器（可选）
        value: str - 填充值（fill动作时）
        x: int - 点击X坐标（可选）
        y: int - 点击Y坐标（可选）
    """
    session_id = data.get('sessionId')
    action = data.get('action')
    logger.info("WS [browser_action] sid=%s - 会话: %s, 动作: %s, 选择器: %s",
                sid, session_id, action, data.get('selector'))

    if not session_id or not action:
        return {'success': False, 'message': '缺少必需参数'}

    valid_actions = ['click', 'fill', 'scroll', 'back', 'forward', 'reload', 'navigate']
    if action not in valid_actions:
        return {'success': False, 'message': f'无效的动作类型，支持: {valid_actions}'}

    # 广播到会话中的所有客户端
    await manager.broadcast_to_session(session_id, 'browser_action', {
        'sessionId': session_id,
        'action': action,
        'selector': data.get('selector'),
        'value': data.get('value'),
        'x': data.get('x'),
        'y': data.get('y'),
        'timestamp': datetime.utcnow().isoformat(),
    }, skip_sid=sid)

    return {'success': True}


# ============================================
# 剪贴板同步事件
# ============================================

@sio.event
async def clipboard_sync(sid, data):
    """
    剪贴板同步：接收客户端发送的剪贴板数据，广播到同用户的其他设备

    请求数据:
        item: dict - 剪贴板条目（含加密内容）

    广播:
        clipboard_sync 事件到同用户的其他设备
    """
    device_info = manager.get_device_info(sid)
    if not device_info:
        return

    user_id = device_info.get('user_id')
    if not user_id:
        return

    item = data.get('item')
    if not item:
        return

    # 广播给同用户的其他设备
    await manager.send_to_user_devices(
        user_id,
        'clipboard_sync',
        {'type': 'clipboard_sync', 'item': item},
        skip_sid=sid
    )
