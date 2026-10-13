#include "windows_ui.h"
#include "bridge.h"
#include <uxtheme.h>
#include <objidl.h>
#include <gdiplus.h>
#include "windows_style.h"
#include <algorithm>
#include <memory>
namespace ui {
HWND list,detail,empty;
HFONT font,titleFont,smallFont;
std::vector<std::wstring> rows;
static HWND parent,refresh,sync,login,copy,more,picture;
static HBRUSH white=nullptr;
static std::wstring displayedState=L"正在连接";
static std::wstring state=L"正在连接";
static std::string selectedId;
static std::vector<std::string> ids;
static std::unique_ptr<Gdiplus::Bitmap> bitmap;
static IStream* imageStream=nullptr;
static ULONG_PTR gdiToken;
std::wstring wide(const char* text){int n=MultiByteToWideChar(CP_UTF8,0,text,-1,nullptr,0);std::wstring out(n,L'\0');MultiByteToWideChar(CP_UTF8,0,text,-1,out.data(),n);out.pop_back();return out;}
// Standard GDI controls do not preserve alpha on an extended DWM frame.
// Composite them into an explicitly opaque buffer so text never becomes glass.
static LRESULT CALLBACK OpaqueControl(HWND w,UINT msg,WPARAM wp,LPARAM lp){
 auto original=(WNDPROC)GetPropW(w,L"Clipboard.OriginalProc");
 if(msg==WM_PAINT){
  PAINTSTRUCT ps;HDC target=BeginPaint(w,&ps);RECT r;GetClientRect(w,&r);HDC dc=nullptr;
  HPAINTBUFFER buffer=BeginBufferedPaint(target,&r,BPBF_TOPDOWNDIB,nullptr,&dc);
  if(buffer){CallWindowProcW(original,w,WM_PRINT,(WPARAM)dc,PRF_CLIENT|PRF_ERASEBKGND);BufferedPaintSetAlpha(buffer,&r,255);EndBufferedPaint(buffer,TRUE);}
  else CallWindowProcW(original,w,WM_PRINTCLIENT,(WPARAM)target,PRF_CLIENT);
  EndPaint(w,&ps);return 0;
 }
 if(msg==WM_SIZE){wchar_t cls[32];GetClassNameW(w,cls,32);if(wcscmp(cls,L"Button")==0){RECT r;GetClientRect(w,&r);SetWindowRgn(w,CreateRoundRectRgn(0,0,r.right+1,r.bottom+1,20,20),TRUE);}}
 auto result=CallWindowProcW(original,w,msg,wp,lp);if(msg==WM_NCDESTROY)RemovePropW(w,L"Clipboard.OriginalProc");return result;
}
static HWND control(const wchar_t* cls,const wchar_t* text,DWORD style,int id){
 HWND w=CreateWindowExW(0,cls,text,WS_CHILD|WS_VISIBLE|style,0,0,1,1,parent,(HMENU)(INT_PTR)id,GetModuleHandleW(nullptr),nullptr);
 SendMessageW(w,WM_SETFONT,(WPARAM)font,TRUE);SetWindowTheme(w,L"Explorer",nullptr);SetPropW(w,L"Clipboard.OriginalProc",(HANDLE)SetWindowLongPtrW(w,GWLP_WNDPROC,(LONG_PTR)OpaqueControl));return w;
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
 parent=window;BufferedPaintInit();style::apply(window);white=CreateSolidBrush(style::colors().surface);HDC dc=GetDC(window);int dpi=GetDeviceCaps(dc,LOGPIXELSY);ReleaseDC(window,dc);
 font=CreateFontW(-MulDiv(10,dpi,72),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");
 smallFont=CreateFontW(-MulDiv(9,dpi,72),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");
 titleFont=CreateFontW(-MulDiv(18,dpi,72),0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Microsoft YaHei UI");
 refresh=control(L"BUTTON",L"刷新",BS_OWNERDRAW|WS_TABSTOP,Refresh);
 sync=control(L"BUTTON",L"同步当前剪贴板",BS_OWNERDRAW|WS_TABSTOP,Sync);
 login=control(L"BUTTON",L"账号",BS_OWNERDRAW|WS_TABSTOP,Login);
 more=control(L"BUTTON",L"更多",BS_OWNERDRAW|WS_TABSTOP,More);
 copy=control(L"BUTTON",L"复制内容",BS_OWNERDRAW|WS_TABSTOP,Copy);EnableWindow(copy,FALSE);
 list=control(L"LISTBOX",L"历史记录",WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_HASSTRINGS|LBS_NOINTEGRALHEIGHT,History);SendMessageW(list,LB_SETITEMHEIGHT,0,84);
 detail=control(L"EDIT",L"选择左侧记录，查看完整内容。",WS_VSCROLL|WS_TABSTOP|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL,107);
 empty=control(L"STATIC",L"暂无记录\n\n登录同一账号后，在任一设备复制内容。",SS_CENTER,108);
 Gdiplus::GdiplusStartupInput input;Gdiplus::GdiplusStartup(&gdiToken,&input,nullptr);
 WNDCLASSW cls={};cls.lpfnWndProc=PictureProc;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"SharedClipboardPreview";RegisterClassW(&cls);
 picture=control(L"SharedClipboardPreview",L"图片预览",0,109);ShowWindow(picture,SW_HIDE);layout(window);
}
void layout(HWND window){
 RECT r;GetClientRect(window,&r);int width=r.right,height=r.bottom;int left=(std::max)(290,(std::min)(360,width*2/5));int right=left+44;
 MoveWindow(sync,width-362,30,156,38,TRUE);MoveWindow(refresh,width-194,30,72,38,TRUE);MoveWindow(login,width-110,30,72,38,TRUE);
 MoveWindow(more,width-110,height-53,72,32,TRUE);MoveWindow(copy,width-184,121,132,34,TRUE);
 MoveWindow(list,36,168,left-24,height-264,TRUE);MoveWindow(empty,44,230,left-40,120,TRUE);
 int paneWidth=width-right-24,paneHeight=height-274;
 bool hasImage=bitmap!=nullptr;
 MoveWindow(detail,right+24,181,paneWidth-48,hasImage?(std::min)(90,paneHeight/3):paneHeight,TRUE);
 MoveWindow(picture,right+24,280,paneWidth-48,(std::max)(80,height-370),TRUE);
 ShowWindow(picture,hasImage?SW_SHOW:SW_HIDE);InvalidateRect(window,nullptr,TRUE);
}
void theme(HWND window){style::apply(window);DeleteObject(white);white=CreateSolidBrush(style::colors().surface);RedrawWindow(window,nullptr,nullptr,RDW_INVALIDATE|RDW_ALLCHILDREN);}
static void text(HDC dc,const wchar_t* value,RECT r,COLORREF color,HFONT f,UINT flags=DT_LEFT|DT_SINGLELINE|DT_VCENTER){
 SetTextColor(dc,color);SetBkMode(dc,TRANSPARENT);SelectObject(dc,f);DrawTextW(dc,value,-1,&r,flags);
}
void render(HWND window,HDC dc){
 RECT r;GetClientRect(window,&r);if(r.right<=0||r.bottom<=0)return;
 // An alpha-preserving DIB leaves the outer canvas translucent for the DWM backdrop.
 // GDI painting an opaque full-window background would hide the acrylic entirely.
 BITMAPINFO info={};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=r.right;info.bmiHeader.biHeight=-r.bottom;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
 void* pixels=nullptr;HBITMAP buffer=CreateDIBSection(dc,&info,DIB_RGB_COLORS,&pixels,nullptr,0);if(!buffer)return;
 HDC memory=CreateCompatibleDC(dc);auto previous=SelectObject(memory,buffer);
 {
  Gdiplus::Bitmap image(r.right,r.bottom,r.right*4,PixelFormat32bppPARGB,(BYTE*)pixels);Gdiplus::Graphics g(&image);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  auto c=style::colors();g.Clear(style::color(c.background,style::glass()?72:255));
  int left=(std::max)(290,(std::min)(360,(int)r.right*2/5));
  RECT panel={24,108,left+24,r.bottom-76},preview={left+44,108,r.right-24,r.bottom-76};
  auto card=[&](RECT box){RECT shadow=box;OffsetRect(&shadow,0,2);style::rounded(g,shadow,17,Gdiplus::Color(12,34,48,88),Gdiplus::Color(0,0,0,0));style::rounded(g,box,16,style::color(c.surface),style::color(c.border));};
  card(panel);card(preview);
  style::label(g,L"共享剪贴板",{28,18,360,56},titleFont,c.text);
  style::label(g,displayedState.c_str(),{30,61,r.right-390,86},smallFont,c.muted);
  style::label(g,L"最近记录",{42,120,left-36,156},font,c.text);
  auto count=std::to_wstring(rows.size());style::label(g,count.c_str(),{left-40,120,left+6,156},smallFont,c.muted,true);
  style::label(g,L"内容预览",{left+66,120,r.right-200,156},font,c.text);
  Gdiplus::Pen divider(style::color(c.border),1);g.DrawLine(&divider,left+68,166,r.right-48,166);
  style::label(g,L"双击记录即可复制 · 关闭窗口后继续同步",{30,r.bottom-55,r.right-150,r.bottom-20},smallFont,c.muted);
 }
 BitBlt(dc,0,0,r.right,r.bottom,memory,0,0,SRCCOPY);SelectObject(memory,previous);DeleteDC(memory);DeleteObject(buffer);
}
void paint(HWND window){PAINTSTRUCT ps;HDC dc=BeginPaint(window,&ps);render(window,dc);EndPaint(window,&ps);}
void draw(const DRAWITEMSTRUCT* i){
 auto c=style::colors();Gdiplus::Graphics g(i->hDC);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
 if(i->CtlID==History){
  if(i->itemID==(UINT)-1)return;bool selected=(i->itemState&ODS_SELECTED)!=0;
  FillRect(i->hDC,&i->rcItem,white);RECT box=i->rcItem;InflateRect(&box,-2,-4);
  if(selected)style::rounded(g,box,12,style::color(c.selected),style::color(c.selected));
  if(i->itemID>=rows.size())return;auto value=rows[i->itemID];auto split=value.find(L"  ");auto device=split==std::wstring::npos?L"剪贴板":value.substr(0,split);auto content=split==std::wstring::npos?value:value.substr(split+2);
  RECT a=i->rcItem;a.left+=18;a.right-=16;a.top+=12;a.bottom=a.top+22;text(i->hDC,device.c_str(),a,selected?c.selectedText:c.muted,smallFont,DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS);
  a.top+=28;a.bottom=i->rcItem.bottom-10;text(i->hDC,content.c_str(),a,selected?c.selectedText:c.text,font,DT_LEFT|DT_SINGLELINE|DT_END_ELLIPSIS);
  if(i->itemState&ODS_FOCUS){RECT focus=box;InflateRect(&focus,-4,-4);DrawFocusRect(i->hDC,&focus);}
 }else{
  bool primary=i->CtlID==Sync||i->CtlID==Copy,disabled=(i->itemState&ODS_DISABLED)!=0,pressed=(i->itemState&ODS_SELECTED)!=0;
  // Paint the button corners in the surrounding surface; the system backdrop remains in the canvas.
  HBRUSH bg=CreateSolidBrush(i->CtlID==Copy?c.surface:c.background);FillRect(i->hDC,&i->rcItem,bg);DeleteObject(bg);
  COLORREF fill=disabled?c.border:primary?c.accent:c.surface;
  RECT box=i->rcItem;if(pressed)OffsetRect(&box,0,1);
  style::rounded(g,box,10,style::color(fill),style::color(primary?fill:c.border));
  wchar_t label[80];GetWindowTextW(i->hwndItem,label,80);text(i->hDC,label,box,disabled?c.muted:primary?c.buttonText:c.text,font,DT_CENTER|DT_SINGLELINE|DT_VCENTER);
  if(i->itemState&ODS_FOCUS){RECT focus=box;InflateRect(&focus,-4,-4);DrawFocusRect(i->hDC,&focus);}
 }
}
void status(const std::wstring& value){state=value;displayedState=value;InvalidateRect(parent,nullptr,FALSE);}
void loadHistory(){displayedState=L"正在读取历史记录…";InvalidateRect(parent,nullptr,FALSE);sc_event(5,"");}
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
HBRUSH color(HDC dc){SetTextColor(dc,style::colors().text);SetBkColor(dc,style::colors().surface);return white;}
void destroy(){resetImage();if(gdiToken)Gdiplus::GdiplusShutdown(gdiToken);DeleteObject(font);DeleteObject(titleFont);DeleteObject(smallFont);DeleteObject(white);BufferedPaintUnInit();}
}
