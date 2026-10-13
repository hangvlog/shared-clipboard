#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <atomic>
#include "bridge.h"
#include "windows_ui.h"
static HWND mainWindow,dialog,userField,passwordField,keyField;
static NOTIFYICONDATAW tray={sizeof(tray)};
static std::wstring connectionStatus=L"正在启动";
static std::atomic<DWORD> lastRevision;
static bool loggedIn=false,historyVisible=false;
static UINT showMessage;
struct Preview {std::string id;std::wstring text;std::vector<unsigned char> image;bool success;};
struct HistoryRow {std::string id;std::wstring text;};
static std::string utf8(const std::wstring& s){int n=WideCharToMultiByte(CP_UTF8,0,s.c_str(),(int)s.size(),nullptr,0,nullptr,nullptr);std::string v(n,'\0');WideCharToMultiByte(CP_UTF8,0,s.c_str(),(int)s.size(),v.data(),n,nullptr,nullptr);return v;}
static std::string value(HWND field){int n=GetWindowTextLengthW(field);std::wstring text(n+1,L'\0');GetWindowTextW(field,text.data(),n+1);text.resize(n);return utf8(text);}
static HWND control(const wchar_t* cls,const wchar_t* text,DWORD style,int x,int y,int w,int h,int id){HWND item=CreateWindowW(cls,text,WS_CHILD|WS_VISIBLE|style,x,y,w,h,dialog,(HMENU)(INT_PTR)id,GetModuleHandleW(nullptr),nullptr);SendMessageW(item,WM_SETFONT,(WPARAM)ui::font,TRUE);return item;}
static void loadHistory(){if(loggedIn){ui::loadHistory();}else{ui::clear();ui::status(L"请先登录，同一账号的记录会显示在这里");}}
static void showMain(){ShowWindow(mainWindow,IsIconic(mainWindow)?SW_RESTORE:SW_SHOW);SetForegroundWindow(mainWindow);historyVisible=true;sc_event(13,"1");loadHistory();}
static LRESULT CALLBACK DialogProc(HWND window,UINT message,WPARAM w,LPARAM l){
 if(message==WM_COMMAND){int id=LOWORD(w);
  if(id==20){auto user=value(userField),password=value(passwordField);if(user.empty()||password.empty()){MessageBoxW(window,L"请填写账号和登录密码。",L"登录",MB_OK);return 0;}ui::status(L"正在登录…");sc_login(user.c_str(),password.c_str(),"");DestroyWindow(window);return 0;}
  if(id==22){auto key=value(keyField);sc_event(11,key.c_str());DestroyWindow(window);return 0;}
 }
 if(message==WM_CTLCOLORSTATIC||message==WM_CTLCOLOREDIT)return (LRESULT)ui::color((HDC)w);
 if(message==WM_CLOSE){DestroyWindow(window);return 0;}
 if(message==WM_APP+7){loggedIn=w!=0;ui::clear();if(loggedIn&&historyVisible)loadHistory();return 0;}
 if(message==WM_DESTROY){dialog=nullptr;userField=passwordField=keyField=nullptr;return 0;}
 return DefWindowProcW(window,message,w,l);
}
static void createDialog(const wchar_t* title,int height){RECT r;GetWindowRect(mainWindow,&r);dialog=CreateWindowExW(WS_EX_DLGMODALFRAME,L"SharedClipboardDialog",title,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU,r.left+120,r.top+120,540,height,mainWindow,nullptr,GetModuleHandleW(nullptr),nullptr);}
static void login(){if(dialog){SetForegroundWindow(dialog);return;}createDialog(L"登录共享剪贴板",265);
 control(L"STATIC",L"使用同一账号，在自己的设备间共享内容。",0,26,24,475,28,0);
 userField=control(L"EDIT",L"",WS_BORDER|ES_AUTOHSCROLL|WS_TABSTOP,136,70,350,28,11);control(L"STATIC",L"账号",0,26,74,100,24,0);
 passwordField=control(L"EDIT",L"",WS_BORDER|ES_PASSWORD|ES_AUTOHSCROLL|WS_TABSTOP,136,112,350,28,12);control(L"STATIC",L"登录密码",0,26,116,100,24,0);
 control(L"STATIC",L"无需设置剪贴板加密密码",0,26,174,260,24,0);
 control(L"BUTTON",L"登录",BS_DEFPUSHBUTTON|WS_TABSTOP,346,168,140,36,20);ShowWindow(dialog,SW_SHOW);SetForegroundWindow(dialog);SetFocus(userField);
}
static void unlock(){if(dialog){SetForegroundWindow(dialog);return;}createDialog(L"解锁旧记录",215);
 control(L"STATIC",L"仅用于读取旧内容，不影响新内容同步。",0,26,24,475,28,0);
 keyField=control(L"EDIT",L"",WS_BORDER|ES_PASSWORD|ES_AUTOHSCROLL|WS_TABSTOP,136,70,350,28,13);control(L"STATIC",L"原密码",0,26,74,100,24,0);
 control(L"BUTTON",L"解锁",BS_DEFPUSHBUTTON|WS_TABSTOP,346,122,140,36,22);ShowWindow(dialog,SW_SHOW);SetForegroundWindow(dialog);SetFocus(keyField);
}
static void menu(){
 HMENU m=CreatePopupMenu();AppendMenuW(m,MF_STRING,1,L"打开主窗口");AppendMenuW(m,MF_SEPARATOR,0,nullptr);
 AppendMenuW(m,MF_STRING,2,L"登录 / 切换账号");AppendMenuW(m,MF_STRING,3,L"解锁旧记录");AppendMenuW(m,MF_STRING,4,L"暂停 / 恢复同步");AppendMenuW(m,MF_STRING,5,L"退出登录");AppendMenuW(m,MF_SEPARATOR,0,nullptr);AppendMenuW(m,MF_STRING,6,L"退出程序");
 POINT pt;GetCursorPos(&pt);SetForegroundWindow(mainWindow);int id=TrackPopupMenu(m,TPM_RETURNCMD|TPM_RIGHTBUTTON,pt.x,pt.y,0,mainWindow,nullptr);DestroyMenu(m);
 if(id==1)showMain();if(id==2)login();if(id==3)unlock();if(id==4)sc_event(7,"");if(id==5){sc_event(8,"");ui::clear();loggedIn=false;}if(id==6)DestroyWindow(mainWindow);
}
static LRESULT CALLBACK WndProc(HWND window,UINT message,WPARAM w,LPARAM l){
 if(message==showMessage&&showMessage){showMain();return 0;}
 if(message==WM_CREATE){ui::create(window);return 0;}
 if(message==WM_SETTINGCHANGE||message==WM_THEMECHANGED||message==WM_DWMCOMPOSITIONCHANGED){ui::theme(window);return 0;}
 if(message==WM_SIZE){ui::layout(window);return 0;}
 if(message==WM_GETMINMAXINFO){auto p=(MINMAXINFO*)l;p->ptMinTrackSize={820,540};return 0;}
 if(message==WM_PRINTCLIENT){ui::render(window,(HDC)w);return 0;}
 if(message==WM_PAINT){ui::paint(window);return 0;}
 if(message==WM_ERASEBKGND)return 1;
 if(message==WM_DRAWITEM){ui::draw((DRAWITEMSTRUCT*)l);return TRUE;}
 if(message==WM_CTLCOLORSTATIC||message==WM_CTLCOLOREDIT||message==WM_CTLCOLORLISTBOX)return (LRESULT)ui::color((HDC)w);
 if(message==WM_COMMAND){int id=LOWORD(w);
  if(id==ui::Refresh)loadHistory();if(id==ui::Sync){if(loggedIn)sc_event(2,"");else login();}if(id==ui::Login)login();if(id==ui::More)menu();
  if(id==ui::History&&HIWORD(w)==LBN_SELCHANGE)ui::select();
  if(id==ui::Copy||(id==ui::History&&HIWORD(w)==LBN_DBLCLK)){auto id=ui::selection();if(!id.empty())sc_event(6,id.c_str());}
  return 0;
 }
 if(message==WM_CLOSE){if(dialog)DestroyWindow(dialog);historyVisible=false;ShowWindow(window,SW_HIDE);sc_event(13,"0");sc_event(9,"");ui::clear();return 0;}
 if(message==WM_CLIPBOARDUPDATE){DWORD revision=GetClipboardSequenceNumber();if(revision!=lastRevision){lastRevision=revision;sc_event(2,"");}return 0;}
 if(message==WM_APP+1){if(l==WM_LBUTTONUP||l==WM_LBUTTONDBLCLK)showMain();if(l==WM_RBUTTONUP)menu();return 0;}
 if(message==WM_APP+2){auto text=(std::wstring*)l;connectionStatus=*text;delete text;ui::status(connectionStatus);wcsncpy_s(tray.szTip,(L"共享剪贴板 · "+connectionStatus).c_str(),_TRUNCATE);tray.uFlags=NIF_TIP;Shell_NotifyIconW(NIM_MODIFY,&tray);
  if(connectionStatus==L"请登录同一个账号"||connectionStatus==L"未登录"||connectionStatus.find(L"登录已过期")!=std::wstring::npos){loggedIn=false;ui::clear();}

  return 0;
 }
 if(message==WM_APP+3){if(historyVisible)ui::begin();return 0;}
 if(message==WM_APP+4){auto row=(HistoryRow*)l;if(historyVisible)ui::add(row->id,row->text);delete row;return 0;}
 if(message==WM_APP+5){if(historyVisible)ui::end();return 0;}
 if(message==WM_APP+6){auto data=(Preview*)l;if(historyVisible)ui::showDetail(data->id,data->text,data->image,data->success);delete data;return 0;}
 if(message==WM_APP+7){loggedIn=w!=0;ui::clear();if(loggedIn&&historyVisible)loadHistory();return 0;}
 if(message==WM_DESTROY){if(dialog)DestroyWindow(dialog);RemoveClipboardFormatListener(window);Shell_NotifyIconW(NIM_DELETE,&tray);native_ws_close();ui::destroy();PostQuitMessage(0);return 0;}
 return DefWindowProcW(window,message,w,l);
}
extern "C" int native_run(){
 showMessage=RegisterWindowMessageW(L"SharedClipboard.ShowMain.v1");HANDLE singleton=CreateMutexW(nullptr,FALSE,L"Local\\SharedClipboard.Native");
 if(GetLastError()==ERROR_ALREADY_EXISTS){HWND existing=FindWindowW(L"SharedClipboardNative",nullptr);if(existing){DWORD pid;GetWindowThreadProcessId(existing,&pid);AllowSetForegroundWindow(pid);PostMessageW(existing,showMessage,0,0);}CloseHandle(singleton);return 0;}
 SetProcessDPIAware();HINSTANCE instance=GetModuleHandleW(nullptr);WNDCLASSW cls={};cls.lpfnWndProc=WndProc;cls.hInstance=instance;cls.lpszClassName=L"SharedClipboardNative";cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);cls.hIcon=LoadIconW(nullptr,IDI_APPLICATION);RegisterClassW(&cls);
 cls.lpfnWndProc=DialogProc;cls.lpszClassName=L"SharedClipboardDialog";cls.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);RegisterClassW(&cls);
 mainWindow=CreateWindowExW(0,L"SharedClipboardNative",L"共享剪贴板",WS_OVERLAPPEDWINDOW|WS_CLIPCHILDREN,CW_USEDEFAULT,CW_USEDEFAULT,1000,680,nullptr,nullptr,instance,nullptr);
 if(!mainWindow||!AddClipboardFormatListener(mainWindow))return 1;
 lastRevision=GetClipboardSequenceNumber();tray.hWnd=mainWindow;tray.uID=1;tray.uFlags=NIF_MESSAGE|NIF_ICON|NIF_TIP;tray.uCallbackMessage=WM_APP+1;tray.hIcon=cls.hIcon;wcscpy_s(tray.szTip,L"共享剪贴板");Shell_NotifyIconW(NIM_ADD,&tray);
 historyVisible=true;SetWindowPos(mainWindow,nullptr,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_SHOWWINDOW);UpdateWindow(mainWindow);sc_start();sc_event(13,"1");
 MSG msg;while(GetMessageW(&msg,nullptr,0,0)>0){if(dialog&&IsDialogMessageW(dialog,&msg))continue;if(IsDialogMessageW(mainWindow,&msg))continue;TranslateMessage(&msg);DispatchMessageW(&msg);}CloseHandle(singleton);return 0;
}
extern "C" void native_status(const char* text){PostMessageW(mainWindow,WM_APP+2,0,(LPARAM)new std::wstring(ui::wide(text)));}
extern "C" void native_history_begin(){PostMessageW(mainWindow,WM_APP+3,0,0);}
extern "C" void native_history_item(const char* id,const char* text){PostMessageW(mainWindow,WM_APP+4,0,(LPARAM)new HistoryRow{id,ui::wide(text)});}
extern "C" void native_history_end(){PostMessageW(mainWindow,WM_APP+5,0,0);}
extern "C" void native_detail(const char* id,const char* text,const unsigned char* image,size_t length,int success){auto p=new Preview{id,ui::wide(text),{},success!=0};if(image&&length)p->image.assign(image,image+length);PostMessageW(mainWindow,WM_APP+6,0,(LPARAM)p);}
extern "C" void native_written(){lastRevision=GetClipboardSequenceNumber();}
extern "C" HWND native_clipboard_owner(){return mainWindow;}
extern "C" void native_clipboard_reset(){lastRevision=GetClipboardSequenceNumber();}

extern "C" void native_session(int logged_in){PostMessageW(mainWindow,WM_APP+7,logged_in,0);}
