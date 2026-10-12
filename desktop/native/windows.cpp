#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <atomic>
#include "bridge.h"
static HWND mainWindow,dialog,userField,passwordField,keyField,listField;
static NOTIFYICONDATAW tray={sizeof(tray)};
static std::wstring status=L"正在启动";
static std::vector<std::wstring> rows;
static std::atomic<DWORD> lastRevision;
static std::wstring wide(const char *s){int n=MultiByteToWideChar(CP_UTF8,0,s,-1,nullptr,0);std::wstring v(n,L'\0');MultiByteToWideChar(CP_UTF8,0,s,-1,v.data(),n);v.pop_back();return v;}
static std::string utf8(const std::wstring &s){int n=WideCharToMultiByte(CP_UTF8,0,s.c_str(),(int)s.size(),nullptr,0,nullptr,nullptr);std::string v(n,'\0');WideCharToMultiByte(CP_UTF8,0,s.c_str(),(int)s.size(),v.data(),n,nullptr,nullptr);return v;}
static std::string value(HWND field){int n=GetWindowTextLengthW(field);std::wstring text(n+1,L'\0');GetWindowTextW(field,text.data(),n+1);text.resize(n);return utf8(text);}
static HWND control(const wchar_t *cls,const wchar_t *text,DWORD style,int x,int y,int w,int h,int id){HWND handle=CreateWindowW(cls,text,WS_CHILD|WS_VISIBLE|style,x,y,w,h,dialog,(HMENU)(INT_PTR)id,GetModuleHandleW(nullptr),nullptr);SendMessageW(handle,WM_SETFONT,(WPARAM)GetStockObject(DEFAULT_GUI_FONT),TRUE);return handle;}
static LRESULT CALLBACK DialogProc(HWND window,UINT message,WPARAM w,LPARAM l){
 if(message==WM_COMMAND){int id=LOWORD(w);if(id==20){auto user=value(userField),password=value(passwordField),key=value(keyField);sc_login(user.c_str(),password.c_str(),key.c_str());DestroyWindow(window);return 0;}if(id==21){int selection=(int)SendMessageW(listField,LB_GETCURSEL,0,0);if(selection>=0)sc_history_select(selection);DestroyWindow(window);return 0;}}
 if(message==WM_CLOSE){DestroyWindow(window);return 0;}
 if(message==WM_DESTROY){sc_event(9,"");rows.clear();dialog=nullptr;userField=passwordField=keyField=listField=nullptr;return 0;}
 return DefWindowProcW(window,message,w,l);
}
static void createDialog(const wchar_t *title,int height){if(dialog){SetForegroundWindow(dialog);return;}dialog=CreateWindowExW(WS_EX_DLGMODALFRAME,L"SharedClipboardDialog",title,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU, CW_USEDEFAULT,CW_USEDEFAULT,560,height,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);}
static void login(){if(dialog){SetForegroundWindow(dialog);return;}createDialog(L"登录共享剪贴板",300);
 control(L"STATIC",L"各设备使用同一账号；加密密码需保持一致。",0,18,16,500,26,0);
 userField=control(L"EDIT",L"",WS_BORDER|ES_AUTOHSCROLL|WS_TABSTOP,160,55,345,26,11);control(L"STATIC",L"账号",0,18,59,140,24,0);
 passwordField=control(L"EDIT",L"",WS_BORDER|ES_PASSWORD|ES_AUTOHSCROLL|WS_TABSTOP,160,96,345,26,12);control(L"STATIC",L"登录密码",0,18,100,140,24,0);
 keyField=control(L"EDIT",L"",WS_BORDER|ES_PASSWORD|ES_AUTOHSCROLL|WS_TABSTOP,160,137,345,26,13);control(L"STATIC",L"加密密码（可选）",0,18,141,140,24,0);
 control(L"BUTTON",L"登录",BS_DEFPUSHBUTTON|WS_TABSTOP,360,194,145,32,20);ShowWindow(dialog,SW_SHOW);SetForegroundWindow(dialog);SetFocus(userField);
}
static void showHistory(){if(dialog){SetForegroundWindow(dialog);return;}createDialog(L"共享剪贴板历史",420);listField=control(L"LISTBOX",L"",WS_BORDER|WS_VSCROLL|LBS_NOTIFY,16,16,510,300,14);for(auto &row:rows)SendMessageW(listField,LB_ADDSTRING,0,(LPARAM)row.c_str());control(L"BUTTON",L"复制并关闭",BS_DEFPUSHBUTTON,350,328,176,32,21);ShowWindow(dialog,SW_SHOW);SetForegroundWindow(dialog);}
static LRESULT CALLBACK WndProc(HWND window,UINT message,WPARAM w,LPARAM l){
 if(message==WM_CLIPBOARDUPDATE){DWORD revision=GetClipboardSequenceNumber();if(revision!=lastRevision){lastRevision=revision;sc_event(2,"");}return 0;}
 if(message==WM_APP+1&&(l==WM_RBUTTONUP||l==WM_LBUTTONUP)){
  HMENU menu=CreatePopupMenu();AppendMenuW(menu,MF_STRING|MF_DISABLED,0,status.c_str());AppendMenuW(menu,MF_SEPARATOR,0,nullptr);
  AppendMenuW(menu,MF_STRING,1,L"登录 / 切换账号");AppendMenuW(menu,MF_STRING,2,L"历史记录");AppendMenuW(menu,MF_STRING,3,L"同步当前剪贴板");AppendMenuW(menu,MF_STRING,4,L"暂停 / 恢复");AppendMenuW(menu,MF_STRING,5,L"退出登录");AppendMenuW(menu,MF_STRING,6,L"退出");POINT point;GetCursorPos(&point);SetForegroundWindow(window);int id=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,point.x,point.y,0,window,nullptr);DestroyMenu(menu);
  if(id==1)login();if(id==2)sc_event(5,"");if(id==3)sc_event(2,"");if(id==4)sc_event(7,"");if(id==5)sc_event(8,"");if(id==6)DestroyWindow(window);return 0;
 }
 if(message==WM_APP+2){auto *text=(std::wstring*)l;status=*text;delete text;wcsncpy_s(tray.szTip,(L"共享剪贴板 · "+status).c_str(),_TRUNCATE);tray.uFlags=NIF_TIP;Shell_NotifyIconW(NIM_MODIFY,&tray);if(status==L"请登录同一个账号")login();return 0;}
 if(message==WM_APP+3){rows.clear();return 0;}
 if(message==WM_APP+4){auto *text=(std::wstring*)l;rows.push_back(*text);delete text;return 0;}
 if(message==WM_APP+5){showHistory();return 0;}
 if(message==WM_DESTROY){RemoveClipboardFormatListener(window);Shell_NotifyIconW(NIM_DELETE,&tray);native_ws_close();PostQuitMessage(0);return 0;}
 return DefWindowProcW(window,message,w,l);
}
extern "C" int native_run(){
 HANDLE singleton=CreateMutexW(nullptr,FALSE,L"Local\\SharedClipboard.Native");if(GetLastError()==ERROR_ALREADY_EXISTS)return 0;
 SetProcessDPIAware();HINSTANCE instance=GetModuleHandleW(nullptr);WNDCLASSW cls={};cls.lpfnWndProc=WndProc;cls.hInstance=instance;cls.lpszClassName=L"SharedClipboardNative";RegisterClassW(&cls);
 cls.lpfnWndProc=DialogProc;cls.lpszClassName=L"SharedClipboardDialog";cls.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);RegisterClassW(&cls);
 mainWindow=CreateWindowExW(0,L"SharedClipboardNative",L"共享剪贴板",0,0,0,0,0,nullptr,nullptr,instance,nullptr);
 if(!mainWindow||!AddClipboardFormatListener(mainWindow))return 1;
 lastRevision=GetClipboardSequenceNumber();tray.hWnd=mainWindow;tray.uID=1;tray.uFlags=NIF_MESSAGE|NIF_ICON|NIF_TIP;tray.uCallbackMessage=WM_APP+1;tray.hIcon=LoadIconW(nullptr,IDI_APPLICATION);wcscpy_s(tray.szTip,L"共享剪贴板");Shell_NotifyIconW(NIM_ADD,&tray);
 sc_start();MSG message;while(GetMessageW(&message,nullptr,0,0)>0){if(dialog&&IsDialogMessageW(dialog,&message))continue;TranslateMessage(&message);DispatchMessageW(&message);}CloseHandle(singleton);return 0;
}
extern "C" void native_status(const char *text){PostMessageW(mainWindow,WM_APP+2,0,(LPARAM)new std::wstring(wide(text)));}
extern "C" void native_history_begin(){PostMessageW(mainWindow,WM_APP+3,0,0);}
extern "C" void native_history_item(const char *text){PostMessageW(mainWindow,WM_APP+4,0,(LPARAM)new std::wstring(wide(text)));}
extern "C" void native_history_end(){PostMessageW(mainWindow,WM_APP+5,0,0);}
extern "C" void native_written(){lastRevision=GetClipboardSequenceNumber();}

extern "C" HWND native_clipboard_owner(){return mainWindow;}

extern "C" void native_clipboard_reset(){lastRevision=GetClipboardSequenceNumber();}
