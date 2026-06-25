"""
剪贴板同步 API

提供跨设备剪贴板同步功能，支持文本内容的实时同步和历史记录。
实时同步通过 Socket.IO 实现（事件定义在 routes/ws.py 的 clipboard_sync 事件中）。
"""
import logging
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import Column, String, Text, DateTime, Integer, Boolean, ForeignKey
from sqlalchemy.orm import Session

from src.database import db_manager, Base, User
from src.auth import get_current_user_required

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/clipboard", tags=["clipboard"])


# ============================================
# 数据模型
# ============================================

class ClipboardItem(Base):
    """剪贴板记录表"""
    __tablename__ = "clipboard_items"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    content = Column(Text, nullable=False)
    content_type = Column(String(20), default="text")  # text, image, file
    device_id = Column(String(100), nullable=False)
    device_name = Column(String(100), default="")
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    preview = Column(Text, nullable=True)  # 图片缩略图 base64
    image_url = Column(Text, nullable=True)  # COS 图片 URL（大图片）
    encrypted = Column(Boolean, default=False)  # 内容是否已加密
    content_hash = Column(String(64), nullable=True)  # 明文内容哈希（用于加密场景去重）


# ============================================
# 请求/响应模型
# ============================================

class AddClipboardRequest(BaseModel):
    content: str
    content_type: str = "text"
    device_id: str
    device_name: str = ""
    preview: Optional[str] = None  # 图片缩略图 base64
    image_url: Optional[str] = None  # COS 图片 URL
    encrypted: bool = False  # 内容是否已加密
    content_hash: Optional[str] = None  # 明文内容哈希（加密时用于去重）


class ClipboardItemResponse(BaseModel):
    id: str
    content: str
    contentType: str
    deviceId: str
    deviceName: str
    createdAt: str
    preview: Optional[str] = None
    imageUrl: Optional[str] = None
    encrypted: bool = False

    class Config:
        from_attributes = True


# ============================================
# API 端点
# ============================================

@router.get("/history")
async def get_clipboard_history(
    limit: int = 200,
    days: Optional[int] = None,
    current_user = Depends(get_current_user_required)
):
    """获取剪贴板历史记录"""
    try:
        with db_manager.session_scope() as db:
            query = db.query(ClipboardItem).filter(
                ClipboardItem.user_id == current_user.id
            )

            if days is not None:
                since = datetime.utcnow() - timedelta(days=days)
                query = query.filter(ClipboardItem.created_at >= since)

            items = query.order_by(
                ClipboardItem.created_at.desc()
            ).limit(limit).all()

            return {
                "code": 1,
                "data": [
                    {
                        "id": item.id,
                        "content": item.content,
                        "contentType": item.content_type,
                        "deviceId": item.device_id,
                        "deviceName": item.device_name,
                        "createdAt": item.created_at.isoformat() if item.created_at else "",
                        "preview": item.preview,
                        "imageUrl": item.image_url,
                        "encrypted": item.encrypted or False,
                    }
                    for item in items
                ]
            }
    except Exception as e:
        logger.error(f"获取剪贴板历史失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/add")
async def add_clipboard_item(
    request: AddClipboardRequest,
    current_user = Depends(get_current_user_required)
):
    """添加剪贴板记录"""
    try:
        # 限制内容长度
        if len(request.content) > 100000:  # 100KB
            raise HTTPException(status_code=400, detail="内容过长，最大支持 100KB")

        with db_manager.session_scope() as db:
            # 检查是否与最近一条重复
            # 加密内容用 content_hash 比较（同一明文加密后密文不同）
            latest = db.query(ClipboardItem).filter(
                ClipboardItem.user_id == current_user.id
            ).order_by(
                ClipboardItem.created_at.desc()
            ).first()

            is_duplicate = False
            if latest:
                if request.encrypted and request.content_hash:
                    is_duplicate = latest.content_hash == request.content_hash
                else:
                    is_duplicate = latest.content == request.content

            if is_duplicate:
                return {
                    "code": 1,
                    "message": "内容重复，跳过",
                    "data": {
                        "id": latest.id,
                        "content": latest.content,
                        "contentType": latest.content_type,
                        "deviceId": latest.device_id,
                        "deviceName": latest.device_name,
                        "createdAt": latest.created_at.isoformat() if latest.created_at else "",
                        "preview": latest.preview,
                        "imageUrl": latest.image_url,
                        "encrypted": latest.encrypted or False,
                    }
                }

            # 创建新记录
            item = ClipboardItem(
                user_id=current_user.id,
                content=request.content,
                content_type=request.content_type,
                device_id=request.device_id,
                device_name=request.device_name,
                preview=request.preview,
                image_url=request.image_url,
                encrypted=request.encrypted,
                content_hash=request.content_hash,
            )
            db.add(item)
            db.flush()

            # 清理旧记录，只保留最近 50 条
            old_items = db.query(ClipboardItem).filter(
                ClipboardItem.user_id == current_user.id
            ).order_by(
                ClipboardItem.created_at.desc()
            ).offset(200).all()

            for old_item in old_items:
                db.delete(old_item)

            return {
                "code": 1,
                "message": "添加成功",
                "data": {
                    "id": item.id,
                    "content": item.content,
                    "contentType": item.content_type,
                    "deviceId": item.device_id,
                    "deviceName": item.device_name,
                    "createdAt": item.created_at.isoformat() if item.created_at else "",
                    "preview": item.preview,
                    "imageUrl": item.image_url,
                    "encrypted": item.encrypted or False,
                }
            }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"添加剪贴板记录失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/sync")
async def sync_clipboard(
    since: Optional[str] = None,
    current_user = Depends(get_current_user_required)
):
    """增量同步：返回 since 之后的新记录 + 当前总数"""
    try:
        with db_manager.session_scope() as db:
            total = db.query(ClipboardItem).filter(
                ClipboardItem.user_id == current_user.id
            ).count()

            query = db.query(ClipboardItem).filter(
                ClipboardItem.user_id == current_user.id
            )

            if since:
                try:
                    since_dt = datetime.fromisoformat(since.replace('Z', '+00:00'))
                    query = query.filter(ClipboardItem.created_at > since_dt)
                except ValueError:
                    raise HTTPException(status_code=400, detail="Invalid since format, use ISO 8601")

            items = query.order_by(
                ClipboardItem.created_at.desc()
            ).limit(200).all()

            return {
                "code": 1,
                "data": {
                    "items": [
                        {
                            "id": item.id,
                            "content": item.content,
                            "contentType": item.content_type,
                            "deviceId": item.device_id,
                            "deviceName": item.device_name,
                            "createdAt": item.created_at.isoformat() if item.created_at else "",
                            "preview": item.preview,
                            "imageUrl": item.image_url,
                            "encrypted": item.encrypted or False,
                        }
                        for item in items
                    ],
                    "total": total,
                    "syncedAt": datetime.utcnow().isoformat(),
                }
            }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"增量同步失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/delete/{item_id}")
async def delete_clipboard_item(
    item_id: str,
    current_user = Depends(get_current_user_required)
):
    """删除剪贴板记录"""
    try:
        with db_manager.session_scope() as db:
            item = db.query(ClipboardItem).filter(
                ClipboardItem.id == item_id,
                ClipboardItem.user_id == current_user.id
            ).first()

            if not item:
                raise HTTPException(status_code=404, detail="记录不存在")

            db.delete(item)
            return {"code": 1, "message": "删除成功"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"删除剪贴板记录失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/clear")
async def clear_clipboard_history(
    current_user = Depends(get_current_user_required)
):
    """清空剪贴板历史"""
    try:
        with db_manager.session_scope() as db:
            db.query(ClipboardItem).filter(
                ClipboardItem.user_id == current_user.id
            ).delete()
            return {"code": 1, "message": "清空成功"}
    except Exception as e:
        logger.error(f"清空剪贴板历史失败: {e}")
        raise HTTPException(status_code=500, detail=str(e))
