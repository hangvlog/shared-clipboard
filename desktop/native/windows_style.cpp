#include "windows_style.h"
#include <dwmapi.h>
namespace style {
static bool backdrop=false;
static Palette palette;
const Palette& colors(){return palette;}
bool glass(){return backdrop;}
Gdiplus::Color color(COLORREF value,BYTE alpha){return Gdiplus::Color(alpha,GetRValue(value),GetGValue(value),GetBValue(value));}
void apply(HWND window){
 HIGHCONTRASTW hc={sizeof(hc)};SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(hc),&hc,0);
 bool contrast=(hc.dwFlags&HCF_HIGHCONTRASTON)!=0;
 DWORD transparency=1,size=sizeof(transparency);
 RegGetValueW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",L"EnableTransparency",RRF_RT_REG_DWORD,nullptr,&transparency,&size);
 palette=contrast?Palette{GetSysColor(COLOR_WINDOW),GetSysColor(COLOR_WINDOW),GetSysColor(COLOR_WINDOWTEXT),GetSysColor(COLOR_WINDOWTEXT),GetSysColor(COLOR_WINDOWTEXT),GetSysColor(COLOR_HIGHLIGHT),GetSysColor(COLOR_HIGHLIGHT),GetSysColor(COLOR_HIGHLIGHTTEXT),GetSysColor(COLOR_HIGHLIGHTTEXT)}:
  Palette{RGB(241,244,250),RGB(255,255,255),RGB(30,38,57),RGB(104,114,135),RGB(224,229,239),RGB(81,91,212),RGB(237,239,255),RGB(30,38,57),RGB(255,255,255)};
 // DWMWA_SYSTEMBACKDROP_TYPE / DWMSBT_TRANSIENTWINDOW: Windows 11 22H2+ desktop acrylic.
 // Unsupported Windows versions, disabled transparency and high contrast use opaque cards.
 int type=!contrast&&transparency?3:1;
 backdrop=SUCCEEDED(DwmSetWindowAttribute(window,38,&type,sizeof(type)))&&type==3;
 MARGINS margins=backdrop?MARGINS{-1,-1,-1,-1}:MARGINS{0,0,0,0};
 if(FAILED(DwmExtendFrameIntoClientArea(window,&margins)))backdrop=false;
 int corner=2;DwmSetWindowAttribute(window,33,&corner,sizeof(corner));
 BOOL dark=FALSE;DwmSetWindowAttribute(window,20,&dark,sizeof(dark));
 COLORREF caption=backdrop?0xFFFFFFFF:palette.background;
 DwmSetWindowAttribute(window,35,&caption,sizeof(caption));
 DwmSetWindowAttribute(window,36,&palette.text,sizeof(palette.text));
 COLORREF border=contrast?palette.border:RGB(211,216,231);
 DwmSetWindowAttribute(window,34,&border,sizeof(border));
 InvalidateRect(window,nullptr,TRUE);
}
void rounded(Gdiplus::Graphics& g,RECT r,float radius,Gdiplus::Color fill,Gdiplus::Color border){
 float x=(float)r.left+0.5f,y=(float)r.top+0.5f,w=(float)(r.right-r.left)-1,h=(float)(r.bottom-r.top)-1,d=radius*2;
 Gdiplus::GraphicsPath p;p.AddArc(x,y,d,d,180,90);p.AddArc(x+w-d,y,d,d,270,90);p.AddArc(x+w-d,y+h-d,d,d,0,90);p.AddArc(x,y+h-d,d,d,90,90);p.CloseFigure();
 Gdiplus::SolidBrush brush(fill);g.FillPath(&brush,&p);
 if(border.GetA()){Gdiplus::Pen pen(border,1);g.DrawPath(&pen,&p);}
}
void label(Gdiplus::Graphics& g,const wchar_t* value,RECT r,HFONT f,COLORREF c,bool right){
 LOGFONTW lf;GetObjectW(f,sizeof(lf),&lf);Gdiplus::Font font(lf.lfFaceName,(float)abs(lf.lfHeight),lf.lfWeight>=FW_SEMIBOLD?Gdiplus::FontStyleBold:Gdiplus::FontStyleRegular,Gdiplus::UnitPixel);
 Gdiplus::SolidBrush brush(color(c));Gdiplus::StringFormat fmt;
 fmt.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);fmt.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);fmt.SetLineAlignment(Gdiplus::StringAlignmentCenter);if(right)fmt.SetAlignment(Gdiplus::StringAlignmentFar);
 g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
 g.DrawString(value,-1,&font,Gdiplus::RectF((float)r.left,(float)r.top,(float)(r.right-r.left),(float)(r.bottom-r.top)),&fmt,&brush);
}
}
