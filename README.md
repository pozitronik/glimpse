# Glimpse

![Plugin screenshot](/img/glimpse.jpg)

A pair of Total Commander plugins for working with video frames. The **WLX** (Lister) plugin displays evenly-spaced video frames when previewing a file. The **WCX** (Packer) plugin presents a video as a virtual archive of frame images, allowing batch extraction via TC's standard file operations.

## WLX Plugin (Lister)

Provides an instant visual summary of a video's content without opening a media player.

### Features

- Fast, non-blocking preview: placeholders appear immediately, frames load in background
- Five view modes: smart grid, grid, scroll, filmstrip, single frame
- Configurable number of frames (1-99)
- Frame selection (Ctrl+Click to toggle, Ctrl+A to select all) with save and clipboard support
- Save frames as PNG or JPEG with configurable quality
- Zoom controls: fit window, fit if larger, actual size, manual zoom
- Optional disk cache for instant re-preview
- Parallel frame extraction with configurable worker count and thread limit
- BMP pipe mode for faster frame extraction (configurable in settings)
- Navigate between video files in the current directory without leaving the preview
- Collapsible toolbar with hamburger overflow menu for narrow windows
- Environment variable expansion in all configured paths (e.g. `%USERPROFILE%`)

### Keyboard Shortcuts

| Key             | Action                                                                                            |
|-----------------|---------------------------------------------------------------------------------------------------|
| Ctrl+1..5       | Switch view mode (smart grid / grid / scroll / filmstrip / single); repeat to cycle zoom submodes |
| +/-             | Zoom in / out                                                                                     |
| 0               | Reset zoom to 1x                                                                                  |
| Left/Right      | Previous / next video file in directory                                                           |
| PageUp/Down     | Previous / next video file in directory                                                           |
| Ctrl+Left/Right | Previous / next frame (single mode)                                                               |
| Ctrl+Up/Down    | Increase / decrease frame count                                                                   |
| Ctrl+A          | Select all                                                                                        |
| Ctrl+Click      | Toggle frame selection                                                                            |
| Ctrl+S          | Save focused frame                                                                                |
| Ctrl+Alt+S      | Save all frames                                                                                   |
| Ctrl+Shift+S    | Save combined image                                                                               |
| Ctrl+C          | Copy focused frame to clipboard                                                                   |
| Ctrl+Shift+C    | Copy combined image to clipboard                                                                  |
| T               | Toggle timecodes                                                                                  |
| R               | Refresh (re-extract all frames)                                                                   |
| Space           | Next video file in directory                                                                      |
| Backspace       | Previous video file in directory                                                                  |
| Z               | Previous video file in directory                                                                  |
| ~               | Open hamburger menu (when toolbar is collapsed)                                                   |
| F2              | Settings                                                                                          |
| F3              | Toggle status bar                                                                                 |
| F4              | Toggle toolbar                                                                                    |

### Configuration

All settings are stored in `Glimpse.ini` in the plugin directory. Access the settings dialog with F2 or via the right-click context menu.

## WCX Plugin (Packer)

Presents a video file as a virtual archive containing frame images. Opening a video in TC shows files like `video_frame_001_00m05s.png` that can be copied, viewed, or batch-extracted using standard TC operations.

### Use Cases

- Batch-extract thumbnails from many videos at once using TC's multi-file copy
- Preview frame filenames before extracting
- Use TC's built-in viewer to browse individual frames

### Configuration

Open the settings dialog via Files > Pack (Alt+F5) > Configure. The WCX plugin uses its own `Glimpse.ini`, separate from the WLX plugin.

Settings include:
- Frame count, skip edges percentage
- Parallel extraction: max workers, thread limit, BMP pipe mode
- Supported file extensions
- FFmpeg path (auto-detected if not specified)
- Output mode: separate frame files or a single combined grid image
- Image format (PNG/JPEG), quality and compression
- Combined image options: column count, cell gap, background color, timestamp overlay

After changing settings, re-enter the video file to see the updated listing.

## Installation

### Automatic (recommended)

Open the Glimpse `.zip` archive in Total Commander. TC will detect `pluginst.inf` and offer to install the plugin automatically. Install the WLX and WCX archives separately.

### Manual

**WLX (Lister):**
1. Extract `Glimpse.wlx` and `Glimpse.wlx64` to a directory of your choice
2. In Total Commander: Configuration > Options > Plugins > Lister (WLX) > Add
3. Browse to `Glimpse.wlx64` (64-bit TC) or `Glimpse.wlx` (32-bit TC)

**WCX (Packer):**
1. Extract `Glimpse.wcx` and `Glimpse.wcx64` to a directory of your choice
2. In Total Commander: Configuration > Options > Plugins > Packer (WCX) > Add
3. Browse to `Glimpse.wcx64` (64-bit TC) or `Glimpse.wcx` (32-bit TC)
4. Associate desired video extensions (e.g. `mp4`, `mkv`)

## Requirements

- Total Commander 10.x or later
- `ffmpeg.exe` in plugin directory, configured path, or system PATH

## Supported Formats

MP4, MKV, AVI, MOV, WMV, WEBM, FLV, TS, M2TS, M4V, 3GP, OGV, MPG, MPEG, VOB, ASF, RM, RMVB, F4V - mostly anything that `ffmpeg` supports.

Additional extensions can be configured in Settings (F2 for WLX, or via the INI file for WCX).

## License

GNU Lesser General Public License (LGPL). See LICENSE file for details.
