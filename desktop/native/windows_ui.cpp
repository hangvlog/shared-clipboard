#include "windows_ui.h"
#include "bridge.h"
#include <uxtheme.h>
#include <objidl.h>
#include <gdiplus.h>
#include <algorithm>
#include <memory>
namespace ui {
HWND list,detail,empty;
HFONT font,titleFont,smallFont;
std::vector<std::wstring> rows;
static HWND parent,connection,refresh,sync,login,copy,more,picture;
static HBRUSH white=CreateSolidBrush(RGB(255,255,255));
static std::wstring state=L"正在连接";
static std::string selectedId;
static std::vector<std::string> ids;
static std::unique_ptr<Gdiplus::Bitmap> bitmap;
static IStream* imageStream=nullptr;
static ULONG_PTR gdiToken;
std::wstring wide(const char* text){int n=MultiByteToWideChar(CP_UTF8,0,text,-1,nullptr,0);std::wstring out(n,L'\0');MultiByteToWideChar(CP_UTF8,0,text,-1,out.data(),n);out.pop_back();return out;}
static HWND control(const wchar_t* cls,const wchar_t* text,DWORD style,int id){
 HWND w=CreateWindowExW(0,cls,text,WS_CHILD|WS_VISIBLE|style,0,0,1,1,parent,(HMENU)(INT_PTR)id,GetModuleHandleW(nullptr),nullptr);
 SendMessageW(w,WM_SETFONT,(WPARAM)font,TRUE);SetWindowTheme(w,L"Explorer",nullptr);return w;
}
static void resetImage(){bitmap.reset();if(imageStream){imageStream->Release();imageStream=nullptr;}}
static LRESULT CALLBACK PictureProc(HWND w,UINT msg,WPARAM wp,LPARAM lp){
 if(msg==WM_PAINT||msg==WM_PRINTCLIENT){PAINTSTRUCT ps;HDC dc=msg==WM_PRINTCLIENT?(HDC)wp:BeginPaint(w,&ps);RECT r;GetClientRect(w,&r);FillRect(dc,&r,white);
  if(bitmap){Gdiplus::Graphics g(dc);g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
   float scale=(std::min)((float)(r.right-24)/bitmap->GetWidth(),(float)(r.bottom-24)/bitmap->GetHeight());
   float width=bitmap->GetWidth()*scale,height=bitmap->GetHeight()*scale;
   g.DrawImage(bitmap.get(),(r.right-width)/2,(r.bottom-height)/2,width,height);}
  if(msg==WM_PAINT)EndPaint(w,&ps);return 0;}
 return DefWindowProcW(w,msg,wp,lp);
}
void create(HWND window){
 parent=window;HDC dc=GetDC(window);int dpi=GetDeviceCaps(dc,LOGPIXELSY);ReleaseDC(window,dc);
 font=CreateFontW(-MulDiv(10,dpi,72),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");
 smallFont=CreateFontW(-MulDiv(9,dpi,72),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");
 titleFont=CreateFontW(-MulDiv(23,dpi,72),0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Microsoft YaHei UI");
 connection=control(L"STATIC",L"正在连接",SS_LEFT,0);SendMessageW(connection,WM_SETFONT,(WPARAM)smallFont,TRUE);
 refresh=control(L"BUTTON",L"刷新",BS_OWNERDRAW|WS_TABSTOP,Refresh);
 sync=control(L"BUTTON",L"同步当前剪贴板",BS_OWNERDRAW|WS_TABSTOP,Sync);
 login=control(L"BUTTON",L"账号",BS_OWNERDRAW|WS_TABSTOP,Login);
 more=control(L"BUTTON",L"更多",BS_OWNERDRAW|WS_TABSTOP,More);
 copy=control(L"BUTTON",L"复制内容",BS_OWNERDRAW|WS_TABSTOP,Copy);EnableWindow(copy,FALSE);
 list=control(L"LISTBOX",L"历史记录",WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_HASSTRINGS|LBS_NOINTEGRALHEIGHT,History);SendMessageW(list,LB_SETITEMHEIGHT,0,78);
 detail=control(L"EDIT",L"选择左侧记录，查看完整内容。",WS_VSCROLL|WS_TABSTOP|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL,107);
 empty=control(L"STATIC",L"暂无记录\n\n登录同一账号后，在任一设备复制内容。",SS_CENTER,108);
 Gdiplus::GdiplusStartupInput input;Gdiplus::GdiplusStartup(&gdiToken,&input,nullptr);
 WNDCLASSW cls={};cls.lpfnWndProc=PictureProc;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"SharedClipboardPreview";RegisterClassW(&cls);
 picture=control(L"SharedClipboardPreview",L"图片预览",0,109);ShowWindow(picture,SW_HIDE);layout(window);
}
void layout(HWND window){
 RECT r;GetClientRect(window,&r);int width=r.right,height=r.bottom;int left=(std::max)(290,(std::min)(380,width*2/5));int right=left+44;
 MoveWindow(connection,30,77,width-60,22,TRUE);
 MoveWindow(sync,width-366,31,156,38,TRUE);MoveWindow(refresh,width-200,31,72,38,TRUE);MoveWindow(login,width-118,31,72,38,TRUE);
 MoveWindow(more,width-118,height-52,72,32,TRUE);MoveWindow(copy,width-274,height-52,142,32,TRUE);
 MoveWindow(list,24,148,left,height-222,TRUE);MoveWindow(empty,40,206,left-32,120,TRUE);
 int paneWidth=width-right-32,paneHeight=height-230;
 bool hasImage=bitmap!=nullptr;
 MoveWindow(detail,right+12,160,paneWidth-24,hasImage?(std::min)(120,paneHeight/3):paneHeight,TRUE);
 MoveWindow(picture,right+12,290,paneWidth-24,(std::max)(100,height-370),TRUE);
 ShowWindow(picture,hasImage?SW_SHOW:SW_HIDE);InvalidateRect(window,nullptr,TRUE);
}
static void text(HDC dc,const wchar_t* value,RECT r,COLORREF color,HFONT f,UINT flags=DT_LEFT|DT_SINGLELINE|DT_VCENTER){
 SetTextColor(dc,color);SetBkMode(dc,TRANSPARENT);SelectObject(dc,f);DrawTextW(dc,value,-1,&r,flags);
}
void render(HWND window,HDC dc){
 RECT r;GetClientRect(window,&r);
 HBRUSH bg=CreateSolidBrush(RGB(245,247,251));FillRect(dc,&r,bg);DeleteObject(bg);
 int left=(std::max)(290,(std::min)(380,(int)r.right*2/5));
 RECT panel={24,118,left+24,r.bottom-68},preview={left+44,118,r.right-24,r.bottom-68};FillRect(dc,&panel,white);FillRect(dc,&preview,white);
 text(dc,L"共享剪贴板",{28,22,350,69},RGB(23,36,59),titleFont);
 text(dc,L"最近记录",{40,121,left,147},RGB(102,116,139),smallFont);
 text(dc,L"内容预览",{left+60,121,r.right-42,149},RGB(102,116,139),smallFont);
 text(dc,L"关闭窗口后，仍会在托盘同步",{30,r.bottom-50,440,r.bottom-18},RGB(102,116,139),smallFont);
}
void paint(HWND window){PAINTSTRUCT ps;HDC dc=BeginPaint(window,&ps);render(window,dc);EndPaint(window,&ps);}
void draw(const DRAWITEMSTRUCT* i){
 if(i->CtlID==History){
  if(i->itemID==(UINT)-1)return;bool selected=(i->itemState&ODS_SELECTED)!=0;
  HBRUSH b=CreateSolidBrush(selected?RGB(230,239,255):RGB(255,255,255));FillRect(i->hDC,&i->rcItem,b);DeleteObject(b);
  if(i->itemID>=rows.size())return;auto value=rows[i->itemID];auto split=value.find(L"  ");auto device=split==std::wstring::npos?L"剪贴板":value.substr(0,split);auto content=split==std::wstring::npos?value:value.substr(split+2);
  RECT a=i->rcItem;a.left+=16;a.right-=12;a.top+=9;a.bottom=a.top+22;text(i->hDC,device.c_str(),a,RGB(86,105,131),smallFont,DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS);
  a.top+=25;a.bottom=i->rcItem.bottom-10;text(i->hDC,content.c_str(),a,RGB(23,36,59),font,DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS);
 }else{
  bool primary=i->CtlID==Sync||i->CtlID==Copy,disabled=(i->itemState&ODS_DISABLED)!=0,pressed=(i->itemState&ODS_SELECTED)!=0;
  COLORREF color=disabled?RGB(226,232,240):primary?(pressed?RGB(29,78,216):RGB(37,99,235)):RGB(255,255,255);
  HBRUSH b=CreateSolidBrush(color);HPEN pen=CreatePen(PS_SOLID,1,primary?color:RGB(219,226,236));auto oldB=SelectObject(i->hDC,b),oldP=SelectObject(i->hDC,pen);RoundRect(i->hDC,i->rcItem.left,i->rcItem.top,i->rcItem.right,i->rcItem.bottom,10,10);SelectObject(i->hDC,oldB);SelectObject(i->hDC,oldP);DeleteObject(b);DeleteObject(pen);
  wchar_t label[80];GetWindowTextW(i->hwndItem,label,80);text(i->hDC,label,i->rcItem,disabled?RGB(130,143,162):primary?RGB(255,255,255):RGB(45,59,80),font,DT_CENTER|DT_SINGLELINE|DT_VCENTER);
  if(i->itemState&ODS_FOCUS){RECT focus=i->rcItem;InflateRect(&focus,-4,-4);DrawFocusRect(i->hDC,&focus);}
 }
}
void status(const std::wstring& value){state=value;SetWindowTextW(connection,value.c_str());}
void loadHistory(){SetWindowTextW(connection,L"正在读取历史记录…");sc_event(5,"");}
void begin(){
 int index=(int)SendMessageW(list,LB_GETCURSEL,0,0);selectedId=index>=0&&index<(int)ids.size()?ids[index]:"";
 rows.clear();ids.clear();SendMessageW(list,LB_RESETCONTENT,0,0);EnableWindow(copy,FALSE);
}
void add(const std::string& id,const std::wstring& row){ids.push_back(id);rows.push_back(row);SendMessageW(list,LB_ADDSTRING,0,(LPARAM)row.c_str());}
void end(){
 ShowWindow(empty,rows.empty()?SW_SHOW:SW_HIDE);status(state);
 if(rows.empty()){SetWindowTextW(detail,L"暂无记录。点击“账号”登录，或同步当前剪贴板。");resetImage();layout(parent);return;}
 auto found=std::find(ids.begin(),ids.end(),selectedId);int index=found==ids.end()?0:(int)(found-ids.begin());SendMessageW(list,LB_SETCURSEL,index,0);select();
}
void clear(){begin();rows.clear();SetWindowTextW(detail,L"选择左侧记录，查看完整内容。");resetImage();layout(parent);ShowWindow(empty,SW_SHOW);}
void select(){int index=(int)SendMessageW(list,LB_GETCURSEL,0,0);if(index<0)return;EnableWindow(copy,FALSE);resetImage();SetWindowTextW(detail,L"正在读取内容…");layout(parent);sc_event(12,ids[index].c_str());}
std::string selection(){int i=(int)SendMessageW(list,LB_GETCURSEL,0,0);return i>=0&&i<(int)ids.size()?ids[i]:"";}
void showDetail(const std::string& id,const std::wstring& value,const std::vector<unsigned char>& bytes,bool success){
 if(id!=selection())return;
 resetImage();SetWindowTextW(detail,value.c_str());
 if(!bytes.empty()){HGLOBAL mem=GlobalAlloc(GMEM_MOVEABLE,bytes.size());void* buffer=GlobalLock(mem);if(buffer){memcpy(buffer,bytes.data(),bytes.size());GlobalUnlock(mem);if(SUCCEEDED(CreateStreamOnHGlobal(mem,TRUE,&imageStream))){bitmap.reset(Gdiplus::Bitmap::FromStream(imageStream));if(bitmap->GetLastStatus()!=Gdiplus::Ok)resetImage();}else GlobalFree(mem);}else GlobalFree(mem);}
 EnableWindow(copy,success&&!selection().empty());layout(parent);
}
HBRUSH color(HDC dc){SetTextColor(dc,RGB(55,69,91));SetBkColor(dc,RGB(255,255,255));return white;}
void destroy(){resetImage();if(gdiToken)Gdiplus::GdiplusShutdown(gdiToken);DeleteObject(font);DeleteObject(titleFont);DeleteObject(smallFont);DeleteObject(white);}
}
