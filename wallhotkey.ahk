#Requires AutoHotkey v2
#SingleInstance Force
SetWorkingDir A_ScriptDir
ProcessSetPriority "Normal"

if not A_IsAdmin {
    try {
        Run("*RunAs `"" A_ScriptFullPath "`"")
    } catch {
        MsgBox("Admin rights required.")
        ExitApp
    }
    ExitApp
}

try {
    DllCall("SetThreadDpiAwarenessContext", "ptr", -3)
}

global Config := Map()
Config["Folder"] := "C:\Users\HiuKhoi\Pictures\Wallpapers"
AppDataDir := A_AppData "\WallHotkey"
if !DirExist(AppDataDir) {
    DirCreate(AppDataDir)
}
Config["IniFile"] := AppDataDir "\wall_settings.ini"
Config["SpanTemp"] := A_Temp "\ahk_span_safe.jpg"
Config["LockTemp"] := A_Temp "\ahk_lock_safe.jpg"
Config["PsScript"] := A_Temp "\ahk_worker.ps1"
Config["Change_LockScreen"] := true
Config["Sync_Accent"] := true
Config["OSD_Size"] := 350
Config["OSD_Y"] := 80
Config["OSD_Hold_Time"] := 150

Config["Key_Indi"] := "^!#i"
Config["Key_Next"] := "^'"
Config["Key_Prev"] := "^+'"
Config["Key_Random"] := "^!r"
Config["Key_Dual"] := "^!d"

global files := []
fileStr := ""
try {
    Loop Files Config["Folder"] "\*.*" {
        if A_LoopFileExt ~= "i)(jpg|jpeg|png|bmp|tif)" {
            fileStr .= A_LoopFileFullPath "`n"
        }
    }
} catch {
    MsgBox("Error reading folder.")
    ExitApp
}
if (fileStr == "") {
    MsgBox("No images found.")
    ExitApp
}
global files := StrSplit(Sort(fileStr), "`n")
files.Pop()

global isDual := false
global isRandom := false
global currIndex := 1
global currentStyle := -1
global indicatorState := 1
global targetPath := ""
global targetPath2 := ""
global targetIsDual := false
global g_OSD := ""

global cache_BGR := -1
global cache_Size := -1
global cache_Type := -1

if FileExist(Config["IniFile"]) {
    try {
        savedFile := IniRead(Config["IniFile"], "State", "LastImage", "")
        isRandom := Integer(IniRead(Config["IniFile"], "State", "Random", 0))
        isDual := Integer(IniRead(Config["IniFile"], "State", "Dual", 0))
        indicatorState := Integer(IniRead(Config["IniFile"], "State", "IndicatorState", 1))
        if (savedFile != "" && FileExist(savedFile)) {
            Loop files.Length {
                if (files[A_Index] == savedFile) {
                    currIndex := A_Index
                    break
                }
            }
        }
    } catch {
        indicatorState := 1
    }
}

try {
    Hotkey(Config["Key_Next"], (*) => InstantTrigger(1))
    Hotkey(Config["Key_Prev"], (*) => InstantTrigger(-1))
    Hotkey(Config["Key_Random"], (*) => ToggleRandom())
    Hotkey(Config["Key_Dual"], (*) => ToggleDual())
    Hotkey(Config["Key_Indi"], (*) => ToggleIndicator())
} catch {
    MsgBox("Error registering hotkeys.")
}

InstantTrigger(step) {
    global currIndex, isRandom, isDual, files, targetPath, targetPath2, targetIsDual
    Loop {
        if (files.Length == 0) {
            MsgBox("No images left!")
            ExitApp
        }
        if (isRandom) {
            currIndex := Random(1, files.Length)
        } else {
            currIndex += step
            if (currIndex > files.Length) {
                currIndex := 1
            } else if (currIndex < 1) {
                currIndex := files.Length
            }
        }
        if FileExist(files[currIndex]) {
            break
        } else {
            files.RemoveAt(currIndex)
            if (!isRandom && step > 0) {
                currIndex--
            }
        }
    }
    path1 := files[currIndex]
    textDisp := StrSplit(path1, "\")[-1]
    if (isDual && files.Length >= 2) {
        idx2 := (currIndex >= files.Length) ? 1 : currIndex + 1
        targetPath := path1
        targetPath2 := files[idx2]
        targetIsDual := true
        textDisp := "Dual: " textDisp
    } else {
        targetPath := path1
        targetIsDual := false
    }
    ShowOSD_New(path1, textDisp)
    SetTimer(BackgroundWork, -10)
}

BackgroundWork() {
    global Config, targetPath, targetPath2, targetIsDual
    finalPath := targetPath
    if (targetIsDual) {
        CombineImages_File(targetPath, targetPath2, Config["SpanTemp"])
        finalPath := Config["SpanTemp"]
        SetStyle("Span")
    } else {
        SetStyle("Fill")
    }
    try {
        DllCall("user32.dll\SystemParametersInfoW", "UInt", 20, "UInt", 0, "Str", finalPath, "UInt", 3)
    } catch {
    }
    if (Config["Change_LockScreen"]) {
        UpdateLockScreen_File(targetPath)
    }
    if (Config["Sync_Accent"]) {
        SetTimer(SyncColor_Smart, -500)
        SetTimer(SyncColor_Smart, -1500)
        SetTimer(SyncColor_Smart, -3000)
    }
    SaveSettings()
    SetTimer(HideOSD, -Config["OSD_Hold_Time"])
}

SaveSettings() {
    global Config, files, currIndex, isRandom, isDual, indicatorState
    try {
        currentFile := (files.Length > 0) ? files[currIndex] : ""
        IniWrite(currentFile, Config["IniFile"], "State", "LastImage")
        IniWrite(isRandom ? 1 : 0, Config["IniFile"], "State", "Random")
        IniWrite(isDual ? 1 : 0, Config["IniFile"], "State", "Dual")
        IniWrite(indicatorState, Config["IniFile"], "State", "IndicatorState")
    } catch {
    }
}

CombineImages_File(img1, img2, outPath) {
    psScript := Config["PsScript"]
    ps := "Param([string]$p1, [string]$p2, [string]$out)`r`n"
    ps .= "Add-Type -AssemblyName System.Drawing`r`n"
    ps .= "$i1 = [System.Drawing.Image]::FromFile($p1)`r`n"
    ps .= "$i2 = [System.Drawing.Image]::FromFile($p2)`r`n"
    ps .= "$w = $i1.Width + $i2.Width`r`n"
    ps .= "$h = [Math]::Max($i1.Height, $i2.Height)`r`n"
    ps .= "$bmp = New-Object System.Drawing.Bitmap($w, $h)`r`n"
    ps .= "$g = [System.Drawing.Graphics]::FromImage($bmp)`r`n"
    ps .= "$g.DrawImage($i1, 0, 0)`r`n"
    ps .= "$g.DrawImage($i2, $i1.Width, 0)`r`n"
    ps .= "$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Jpeg)`r`n"
    ps .= "$g.Dispose(); $i1.Dispose(); $i2.Dispose(); $bmp.Dispose()"
    if FileExist(psScript) {
        FileDelete(psScript)
    }
    FileAppend(ps, psScript)
    try {
        RunWait("powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" psScript "`" -p1 `"" img1 "`" -p2 `"" img2 "`" -out `"" outPath "`"", , "Hide")
    } catch {
    }
}

UpdateLockScreen_File(srcPath) {
    psScript := Config["PsScript"]
    tempImg := Config["LockTemp"]
    try {
        FileCopy(srcPath, tempImg, 1)
    } catch {
        tempImg := srcPath
    }
    ps := "Param([string]$p)`r`n"
    ps .= "Add-Type -AssemblyName System.Runtime.WindowsRuntime`r`n"
    ps .= "$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 })[0]`r`n"
    ps .= "$file = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]::GetFileFromPathAsync($p).GetResults()`r`n"
    ps .= "$op = [Windows.System.UserProfile.LockScreen,Windows.System.UserProfile,ContentType=WindowsRuntime]::SetImageFileAsync($file)`r`n"
    ps .= "$asTask.Invoke($null, @($op)).Wait()"
    if FileExist(psScript) {
        FileDelete(psScript)
    }
    FileAppend(ps, psScript)
    try {
        Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" psScript "`" -p `"" tempImg "`"", , "Hide")
    } catch {
    }
}

SyncColor_Smart() {
    global indicatorState, cache_BGR, cache_Size, cache_Type
    try {
        rawDwm := RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM", "AccentColor")
        pureBGR := Integer(rawDwm & 0xFFFFFF)

        if (pureBGR == cache_BGR) {
            mode := Integer(indicatorState)
            targetSize := (mode == 2) ? 5 : 1
            targetType := (mode == 0) ? 0 : 1
            if (targetSize == cache_Size && targetType == cache_Type) {
                return
            }
        }

        cache_BGR := pureBGR

        blue := (pureBGR >> 16) & 0xFF
        green := (pureBGR >> 8) & 0xFF
        red := pureBGR & 0xFF
        rgbStr := red . " " . green . " " . blue

        RegWrite(rgbStr, "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Colors", "Hilight")
        RegWrite("255 255 255", "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Colors", "HilightText")
        RegWrite(rgbStr, "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Colors", "HotTrackingColor")
        RegWrite(rgbStr, "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Colors", "MenuHilight")
        RegWrite(rgbStr, "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Colors", "ActiveBorder")

        elements := Buffer(20, 0)
        NumPut("Int", 13, elements, 0)
        NumPut("Int", 26, elements, 4)
        NumPut("Int", 29, elements, 8)
        NumPut("Int", 10, elements, 12)
        NumPut("Int", 6, elements, 16)

        colors := Buffer(20, 0)
        NumPut("UInt", pureBGR, colors, 0)
        NumPut("UInt", pureBGR, colors, 4)
        NumPut("UInt", pureBGR, colors, 8)
        NumPut("UInt", pureBGR, colors, 12)
        NumPut("UInt", pureBGR, colors, 16)

        DllCall("user32\SetSysColors", "Int", 5, "Ptr", elements.Ptr, "Ptr", colors.Ptr)

        fullAlphaColor := (0xFF << 24) | pureBGR
        ApplyIndicatorStrict(fullAlphaColor)
    } catch {
    }
}

ApplyIndicatorStrict(colorValue) {
    global indicatorState, cache_Size, cache_Type
    cPath := "HKEY_CURRENT_USER\Software\Microsoft\Accessibility\CursorIndicator"
    mode := Integer(indicatorState)

    if (mode == 0) {
        if (cache_Type != 0) {
             try {
                RegWrite(0, "REG_DWORD", cPath, "IndicatorType")
                RefreshIndicator()
                cache_Type := 0
             } catch {
             }
        }
        return
    }

    tSize := (mode == 2) ? 5 : 1

    changed := false
    try {
        if (RegRead(cPath, "IndicatorSize", -1) != tSize) {
            RegWrite(tSize, "REG_DWORD", cPath, "IndicatorSize")
            changed := true
        }
        if (RegRead(cPath, "IndicatorColor", 0) != colorValue) {
            RegWrite(colorValue, "REG_DWORD", cPath, "IndicatorColor")
            changed := true
        }
        if (RegRead(cPath, "IndicatorType", -1) != 1) {
            RegWrite(1, "REG_DWORD", cPath, "IndicatorType")
            changed := true
        }
    } catch {
    }

    if (changed) {
        RefreshIndicator()
    }

    cache_Size := tSize
    cache_Type := 1
}

RefreshIndicator() {
    try {
        DllCall("User32\SystemParametersInfo", "UInt", 0x0057, "UInt", 0, "Ptr", 0, "UInt", 3)
        DllCall("user32\PostMessage", "Ptr", 0xFFFF, "UInt", 0x001A, "Ptr", 0, "Ptr", 0)
    } catch {
    }
}

SetStyle(style) {
    global currentStyle
    if (style == currentStyle) {
        return
    }
    val := (style == "Span") ? "22" : "10"
    try {
        RegWrite(val, "REG_SZ", "HKCU\Control Panel\Desktop", "WallpaperStyle")
        RegWrite("0", "REG_SZ", "HKCU\Control Panel\Desktop", "TileWallpaper")
    } catch {
    }
    currentStyle := style
    try {
        DllCall("user32.dll\SystemParametersInfoW", "UInt", 20, "UInt", 0, "Ptr", 0, "UInt", 0)
    } catch {
    }
}

ToggleRandom() {
    global isRandom
    isRandom := !isRandom
    SaveSettings()
    ShowOSD_New("", "Random: " (isRandom ? "ON" : "OFF"))
    SetTimer(HideOSD, -1000)
}

ToggleDual() {
    global isDual
    isDual := !isDual
    SaveSettings()
    ShowOSD_New("", "Dual Span: " (isDual ? "ON" : "OFF"))
    SetTimer(HideOSD, -1000)
}

ToggleIndicator() {
    global indicatorState
    indicatorState := (indicatorState + 1 > 2) ? 0 : indicatorState + 1
    SaveSettings()

    global cache_BGR
    cache_BGR := -1

    SetTimer(SyncColor_Smart, 10)

    stateText := (indicatorState == 0) ? "OFF" : (indicatorState == 1) ? "NORMAL" : "BIG"
    ShowOSD_New("", "Indicator: " stateText)
    SetTimer(HideOSD, -1000)
}

ShowOSD_New(imgPath, textStr) {
    global g_OSD, Config

    SetTimer(HideOSD, 0)

    if (IsSet(g_OSD) && g_OSD) {
        try g_OSD.Destroy()
        g_OSD := ""
    }

    g_OSD := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner +E0x20 +E0x02000000")
    g_OSD.BackColor := "1F1F1F"
    g_OSD.SetFont("s10 cE0E0E0", "Segoe UI")

    if (imgPath != "" && FileExist(imgPath)) {
        try {
            g_OSD.Add("Picture", "w" Config["OSD_Size"] " h-1 +Border BackgroundTrans", imgPath)
        } catch {
        }
    }

    if (IsObject(g_OSD)) {
        try {
            g_OSD.Add("Text", "Center w" Config["OSD_Size"] " y+8 BackgroundTrans", textStr)
            g_OSD.Show("NoActivate AutoSize xCenter y" Config["OSD_Y"])
            WinSetTransparent(230, g_OSD.Hwnd)
        } catch {
        }
    }
}

HideOSD() {
    global g_OSD
    if (IsSet(g_OSD) && g_OSD) {
        try g_OSD.Destroy()
        g_OSD := ""
    }
}
