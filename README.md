# VideoThumb

A Total Commander Lister plugin (`.wlx` / `.wlx64`) that displays evenly-spaced video frames when previewing a video file with F3 or Ctrl+Q. Provides an instant visual summary of a video's content without opening a media player.

## Features

- Fast, non-blocking preview: placeholders appear immediately, frames load in background
- Five view modes: smart grid, grid, scroll, filmstrip, single frame
- Configurable number of frames (1-99)
- Frame selection (Ctrl+Click to toggle, Ctrl+A to select all) with save and clipboard support
- Save frames as PNG or JPEG with configurable quality
- Zoom controls: fit window, fit if larger, actual size, manual zoom
- Optional disk cache for instant re-preview
- Parallel frame extraction with configurable worker count

## Installation

### Automatic (recommended)

Open the VideoThumb `.zip` archive in Total Commander. TC will detect `pluginst.inf` and offer to install the plugin automatically.

### Manual

1. Extract `VideoThumb.wlx` and `VideoThumb.wlx64` to a directory of your choice
2. In Total Commander: Configuration -> Options -> Plugins -> Lister (WLX) -> Add
3. Browse to `VideoThumb.wlx64` (64-bit TC) or `VideoThumb.wlx` (32-bit TC)

## Requirements

- Total Commander 10.x or later
- `ffmpeg.exe` in plugin directory, configured path, or system PATH
- If FFmpeg is not found, the plugin will prompt to browse for it

## Supported Formats

MP4, MKV, AVI, MOV, WMV, WEBM, FLV, TS, M2TS, M4V, 3GP, OGV, MPG, MPEG, VOB, ASF, RM, RMVB, F4V

Additional extensions can be configured in Settings (F2).

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+1..5 | Switch view mode (smart grid / grid / scroll / filmstrip / single); repeat to cycle zoom submodes |
| +/- | Zoom in / out |
| 0 | Reset zoom to 1x |
| Left/Right | Previous / next frame (single mode) |
| Ctrl+Up/Down | Increase / decrease frame count |
| Ctrl+A | Select all |
| Ctrl+Click | Toggle frame selection |
| Ctrl+S | Save focused frame |
| Ctrl+Alt+S | Save all frames |
| Ctrl+Shift+S | Save combined image |
| Ctrl+C | Copy focused frame to clipboard |
| Ctrl+Shift+C | Copy combined image to clipboard |
| R | Refresh (re-extract all frames) |
| F2 | Settings |
| F3 | Toggle status bar |
| F4 | Toggle toolbar |

## Configuration

All settings are stored in `VideoThumb.ini` in the plugin directory. Access the settings dialog with F2 or via the right-click context menu.

## License

GNU Lesser General Public License (LGPL). See LICENSE file for details.
