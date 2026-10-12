#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <string>
#include <vector>
#include "bridge.h"
extern "C" void native_written();
extern "C" HWND native_clipboard_owner();
static UINT pngFormat(){return RegisterClipboardFormatW(L"PNG");}
extern "C" char *native_clipboard_text(){
 std::string output;if(!OpenClipboard(native_clipboard_owner()))return _strdup("");
 if(!IsClipboardFormatAvailable(CF_HDROP)){
  HANDLE data=GetClipboardData(CF_UNICODETEXT);if(data){auto *text=(const wchar_t*)GlobalLock(data);if(text){size_t max=GlobalSize(data)/sizeof(wchar_t);size_t len=wcsnlen(text,max);if(len<=100000){int n=WideCharToMultiByte(CP_UTF8,0,text,(int)len,nullptr,0,nullptr,nullptr);output.resize(n);WideCharToMultiByte(CP_UTF8,0,text,(int)len,output.data(),n,nullptr,nullptr);}GlobalUnlock(data);}}
 }CloseClipboard();return _strdup(output.c_str());
}
// GDI+ is initialized only while converting a changed image, never by an idle timer.
struct Imaging { ULONG_PTR token=0; Imaging(){Gdiplus::GdiplusStartupInput i;Gdiplus::GdiplusStartup(&token,&i,nullptr);} ~Imaging(){if(token)Gdiplus::GdiplusShutdown(token);} };
static std::vector<unsigned char> encodePng(Gdiplus::Bitmap &bitmap){
 if(bitmap.GetLastStatus()!=Gdiplus::Ok||(unsigned long long)bitmap.GetWidth()*bitmap.GetHeight()>16000000)return {};
 const CLSID png={0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
 IStream *stream=nullptr;if(FAILED(CreateStreamOnHGlobal(nullptr,TRUE,&stream)))return {};
 std::vector<unsigned char> out;
 if(bitmap.Save(stream,&png,nullptr)==Gdiplus::Ok){STATSTG st={};stream->Stat(&st,STATFLAG_NONAME);if(st.cbSize.QuadPart<=2*1024*1024){LARGE_INTEGER zero={};stream->Seek(zero,STREAM_SEEK_SET,nullptr);out.resize((size_t)st.cbSize.QuadPart);ULONG n=0;stream->Read(out.data(),(ULONG)out.size(),&n);if(n!=out.size())out.clear();}}
 stream->Release();return out;
}
extern "C" unsigned char *native_clipboard_png(size_t *length){
 *length=0;std::vector<unsigned char> bytes;if(!OpenClipboard(native_clipboard_owner()))return nullptr;
 if(!IsClipboardFormatAvailable(CF_HDROP)){
  HANDLE data=GetClipboardData(pngFormat());
  if(data){SIZE_T size=GlobalSize(data);if(size>0&&size<=2*1024*1024){void *memory=GlobalLock(data);if(memory){bytes.assign((unsigned char*)memory,(unsigned char*)memory+size);GlobalUnlock(data);}}else *length=SIZE_MAX;}
  else {HBITMAP bitmap=(HBITMAP)GetClipboardData(CF_BITMAP);if(bitmap){BITMAP info={};GetObjectW(bitmap,sizeof(info),&info);if((unsigned long long)info.bmWidth*info.bmHeight<=16000000){Imaging imaging;Gdiplus::Bitmap image(bitmap,nullptr);bytes=encodePng(image);}if(bytes.empty())*length=SIZE_MAX;}}
 }
 CloseClipboard();if(bytes.empty())return nullptr;*length=bytes.size();auto *output=(unsigned char*)malloc(*length);memcpy(output,bytes.data(),*length);return output;
}
extern "C" int native_clipboard_write(const char *text,const unsigned char *image,size_t length){
 if(length>2*1024*1024)return 0;
 HGLOBAL dib=nullptr;std::vector<unsigned char> png;
 if(length){
  Imaging imaging;HGLOBAL source=GlobalAlloc(GMEM_MOVEABLE,length);if(!source)return 0;void *p=GlobalLock(source);memcpy(p,image,length);GlobalUnlock(source);
  IStream *stream=nullptr;if(FAILED(CreateStreamOnHGlobal(source,TRUE,&stream))){GlobalFree(source);return 0;}
  {Gdiplus::Bitmap bitmap(stream);png=encodePng(bitmap);if(!png.empty()){
    UINT w=bitmap.GetWidth(),h=bitmap.GetHeight();size_t size=(size_t)w*h*4;dib=GlobalAlloc(GMEM_MOVEABLE,sizeof(BITMAPINFOHEADER)+size);
    if(dib){auto *header=(BITMAPINFOHEADER*)GlobalLock(dib);*header={sizeof(BITMAPINFOHEADER),(LONG)w,-(LONG)h,1,32,BI_RGB,(DWORD)size,0,0,0,0};
      Gdiplus::BitmapData bd={};Gdiplus::Rect rect(0,0,w,h);
      if(bitmap.LockBits(&rect,Gdiplus::ImageLockModeRead,PixelFormat32bppARGB,&bd)==Gdiplus::Ok){for(UINT y=0;y<h;++y)memcpy((BYTE*)(header+1)+(size_t)y*w*4,(BYTE*)bd.Scan0+(ptrdiff_t)y*bd.Stride,(size_t)w*4);bitmap.UnlockBits(&bd);GlobalUnlock(dib);}else{GlobalUnlock(dib);GlobalFree(dib);dib=nullptr;}
    }
  }}stream->Release();if(png.empty()||!dib){if(dib)GlobalFree(dib);return 0;}
 }
 int n=MultiByteToWideChar(CP_UTF8,0,text,-1,nullptr,0);HGLOBAL stringMemory=nullptr,imageMemory=nullptr;
 if(*text){stringMemory=GlobalAlloc(GMEM_MOVEABLE,n*sizeof(wchar_t));if(!stringMemory){if(dib)GlobalFree(dib);return 0;}void *p=GlobalLock(stringMemory);MultiByteToWideChar(CP_UTF8,0,text,-1,(wchar_t*)p,n);GlobalUnlock(stringMemory);}
 if(!png.empty()){imageMemory=GlobalAlloc(GMEM_MOVEABLE,png.size());if(!imageMemory){if(stringMemory)GlobalFree(stringMemory);if(dib)GlobalFree(dib);return 0;}void *p=GlobalLock(imageMemory);memcpy(p,png.data(),png.size());GlobalUnlock(imageMemory);}
 if(!OpenClipboard(native_clipboard_owner())){if(stringMemory)GlobalFree(stringMemory);if(imageMemory)GlobalFree(imageMemory);if(dib)GlobalFree(dib);return 0;}
 EmptyClipboard();bool ok=true;if(stringMemory&&!SetClipboardData(CF_UNICODETEXT,stringMemory)){GlobalFree(stringMemory);ok=false;}if(imageMemory&&!SetClipboardData(pngFormat(),imageMemory)){GlobalFree(imageMemory);ok=false;}if(dib&&!SetClipboardData(CF_DIB,dib)){GlobalFree(dib);ok=false;}
 native_written();CloseClipboard();return ok;
}
