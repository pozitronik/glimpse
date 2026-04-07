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
- Scaled extraction: automatically downscale frames to display size, reducing memory usage and improving speed for high-resolution video
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

#### General

| Setting                      | Default     | Description                                                                                                              |
|------------------------------|-------------|--------------------------------------------------------------------------------------------------------------------------|
| Skip edges                   | 2%          | Percentage of video duration to skip at the beginning and end, avoiding black intros/outros                              |
| Max workers                  | 1           | Number of parallel ffmpeg processes for frame extraction. More workers = faster loading, higher CPU usage                |
| One per frame                | Off         | Launches a separate worker for each frame instead of using a fixed worker count                                          |
| Limit workers count          | No limit    | When "One per frame" is active, caps the total number of simultaneous workers. 0 = auto (matches CPU core count)         |
| Use BMP pipe                 | On          | Transfers frames via BMP pipe instead of temporary PNG files. Faster but uses more memory                                |
| Scale frames to display size | Off         | Tells ffmpeg to downscale frames to match the current display size. Significantly faster for high-resolution video (4K+) |
| Min side (px)                | 120         | Minimum allowed frame dimension (bigger side) when scaled extraction is active. Prevents frames from becoming too small  |
| Max side (px)                | 1920        | Maximum allowed frame dimension (bigger side) when scaled extraction is active. Caps upscaling for low-res video         |
| Extensions                   | mp4,mkv,... | Comma-separated list of video file extensions the plugin will handle                                                     |
| FFmpeg path                  | Auto-detect | Explicit path to `ffmpeg.exe`. Leave empty to auto-detect from plugin directory or system PATH                           |

#### Appearance

| Setting          | Default       | Description                                                                    |
|------------------|---------------|--------------------------------------------------------------------------------|
| Background       | Dark grey     | Background color behind the frame grid                                         |
| Timecode bg      | Dark grey     | Background color of the timecode overlay on each frame                         |
| Timecode opacity | 180           | Opacity of the timecode background (0 = fully transparent, 255 = fully opaque) |
| Timestamp font   | Segoe UI, 8pt | Font face and size for timecode labels on frames                               |
| Show toolbar     | On            | Display the toolbar at the top of the lister window (F4 to toggle)             |
| Show status bar  | On            | Display the status bar at the bottom of the lister window (F3 to toggle)       |

#### Save

| Setting                  | Default | Description                                                                            |
|--------------------------|---------|----------------------------------------------------------------------------------------|
| Format                   | PNG     | Image format for saved frames (PNG or JPEG)                                            |
| JPEG quality             | 90      | Compression quality for JPEG output (1-100, higher = better quality, larger file)      |
| PNG compression          | 6       | Compression level for PNG output (0-9, higher = smaller file, slower save)             |
| Default folder           | (empty) | Default destination folder for saved frames. Empty = prompt every time                 |
| Include file info banner | Off     | Adds a header with video file name, resolution, and duration to combined image exports |

#### Cache

| Setting           | Default              | Description                                                                                     |
|-------------------|----------------------|-------------------------------------------------------------------------------------------------|
| Enable disk cache | On                   | Caches extracted frames on disk so re-opening the same video loads instantly                    |
| Folder            | %TEMP%\Glimpse\cache | Directory for cached frame files. Supports environment variables                                |
| Max size          | 500 MB               | Maximum total size of the cache directory. Oldest entries are evicted when the limit is reached |

## WCX Plugin (Packer)

Presents a video file as a virtual archive containing frame images. Opening a video in TC shows files like `video_frame_001_00m05s.png` that can be copied, viewed, or batch-extracted using standard TC operations.

### Use Cases

- Batch-extract thumbnails from many videos at once using TC's multi-file copy
- Preview frame filenames before extracting
- Use TC's built-in viewer to browse individual frames

### Configuration

Open the settings dialog via Files > Pack (Alt+F5) > Configure. The WCX plugin uses its own `Glimpse.ini`, separate from the WLX plugin. After changing settings, re-enter the video file to see the updated listing.

#### General

| Setting             | Default     | Description                                                                   |
|---------------------|-------------|-------------------------------------------------------------------------------|
| Frame count         | 4           | Number of frames to extract from the video (1-99)                             |
| Skip edges          | 2%          | Percentage of video duration to skip at the beginning and end                 |
| Max workers         | 1           | Number of parallel ffmpeg processes for frame extraction                      |
| One per frame       | Off         | Launches a separate worker for each frame                                     |
| Limit workers count | No limit    | When "One per frame" is active, caps the total number of simultaneous workers |
| Use BMP pipe        | On          | Transfers frames via BMP pipe instead of temporary files                      |
| FFmpeg path         | Auto-detect | Explicit path to `ffmpeg.exe`. Leave empty to auto-detect                     |

#### Output

| Setting         | Default         | Description                                                                                                  |
|-----------------|-----------------|--------------------------------------------------------------------------------------------------------------|
| Output mode     | Separate frames | `Separate frames` shows individual image files in the archive; `Combined image` produces a single grid image |
| Image format    | PNG             | Image format for extracted frames (PNG or JPEG)                                                              |
| JPEG quality    | 90              | Compression quality for JPEG output (1-100)                                                                  |
| PNG compression | 6               | Compression level for PNG output (0-9)                                                                       |
| Show file sizes | Off             | Displays actual file sizes in the archive listing. Requires extracting all frames when entering the archive  |

#### Combined image

These settings only apply when output mode is set to "Combined image":

| Setting                  | Default       | Description                                                              |
|--------------------------|---------------|--------------------------------------------------------------------------|
| Columns                  | 0 (auto)      | Number of columns in the grid. 0 = automatic layout based on frame count |
| Cell gap (px)            | 2             | Spacing in pixels between frames in the grid                             |
| Background               | Black         | Background color visible in cell gaps and margins                        |
| Show timestamps          | On            | Overlays timecode labels on each frame                                   |
| Timestamp font           | Segoe UI, 8pt | Font face and size for timecode labels                                   |
| Include file info banner | Off           | Adds a header with video file name, resolution, and duration             |

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
