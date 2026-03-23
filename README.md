# VideoThumb

A Total Commander Lister plugin (`.wlx` / `.wlx64`) that displays evenly-spaced video frames when previewing a video file with F3 or Ctrl+Q. Provides an instant visual summary of a video's content without opening a media player.

## Features

- Fast, non-blocking preview: placeholders appear immediately, frames load in background
- Grid and scroll view modes
- Configurable number of frames (1-99)
- Frame selection (single, multi-select, range) with save and clipboard support
- Save frames as PNG or JPEG with configurable quality
- Drag-and-drop frames to file manager or desktop
- Zoom controls: fit window, fit if larger, actual size, manual zoom
- Optional disk cache for instant re-preview
- Uses FFmpeg shared libraries (primary) with `ffmpeg.exe` CLI fallback

## Installation

### Automatic (recommended)

Open the VideoThumb `.zip` archive in Total Commander. TC will detect `pluginst.inf` and offer to install the plugin automatically.

### Manual

1. Extract `VideoThumb.wlx` and `VideoThumb.wlx64` to a directory of your choice
2. In Total Commander: Configuration -> Options -> Plugins -> Lister (WLX) -> Add
3. Browse to `VideoThumb.wlx64` (64-bit TC) or `VideoThumb.wlx` (32-bit TC)

## Requirements

- Total Commander 10.x or later
- FFmpeg: either shared libraries (`avcodec`, `avformat`, `avutil`, `swscale`) or `ffmpeg.exe`
- If FFmpeg is not found, the plugin will offer to download it automatically

## Supported Formats

MP4, MKV, AVI, MOV, WMV, WEBM, FLV, TS, M2TS, M4V, 3GP, OGV, MPG, MPEG, VOB, ASF, RM, RMVB, F4V

Additional extensions can be configured in Settings (F2).

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Tab | Toggle Grid / Scroll mode |
| G / S | Switch to Grid / Scroll mode |
| +/- | Zoom in / out |
| Ctrl+0 | Reset zoom |
| Arrow keys | Move focus |
| Space | Toggle selection |
| Ctrl+A | Select all |
| Escape | Deselect all |
| Enter | Save focused frame |
| Ctrl+S | Save all frames |
| Ctrl+Shift+S | Save selected frames |
| Ctrl+C | Copy focused frame to clipboard |
| R | Reload (re-extract) |
| F2 | Settings |

## Configuration

All settings are stored in `VideoThumb.ini` in the plugin directory. Access the settings dialog with F2 or via the right-click context menu.

## License

GNU Lesser General Public License (LGPL). See LICENSE file for details.
