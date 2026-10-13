#pragma once
#include <windows.h>
#include <string>
#include <vector>
namespace ui {
constexpr int Refresh=101,Sync=102,Login=103,Copy=104,More=105,History=106;
extern HWND list,detail,empty;
extern HFONT font,titleFont,smallFont;
extern std::vector<std::wstring> rows;
std::wstring wide(const char* text);
void create(HWND window);
void layout(HWND window);
void paint(HWND window);
void render(HWND window,HDC dc);
void draw(const DRAWITEMSTRUCT* item);
void status(const std::wstring& text);
void loadHistory();
void begin();
void add(const std::string& id,const std::wstring& row);
std::string selection();
void end();
void clear();
void select();
void showDetail(const std::string& id,const std::wstring& text,const std::vector<unsigned char>& bytes,bool success);
void destroy();
HBRUSH color(HDC dc);
}
