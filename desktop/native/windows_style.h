#pragma once
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
namespace style {
struct Palette { COLORREF background, surface, text, muted, border, accent, selected, selectedText, buttonText; };
const Palette& colors();
bool glass();
void apply(HWND window);
void rounded(Gdiplus::Graphics& g, RECT rect, float radius, Gdiplus::Color fill, Gdiplus::Color border);
void label(Gdiplus::Graphics& g, const wchar_t* value, RECT rect, HFONT font, COLORREF color, bool right=false);
Gdiplus::Color color(COLORREF value, BYTE alpha=255);
}
