# Glimpse

![Plugin screenshot](/img/glimpse.jpg)

A pair of Total Commander plugins for working with video frames. The **WLX** (Lister) plugin displays evenly-spaced video frames when previewing a file. The **WCX** (Packer) plugin presents a video as a virtual archive of frame images, allowing batch extraction via TC's standard file operations.

## WLX Plugin (Lister)

Provides an instant visual summary of a video's content without opening a media player.

### Keyboard Shortcuts

All shortcuts below are defaults. Every row is user-configurable via the **Hotkeys** tab in Settings — bindings can be added, removed, or replaced, and each action can carry more than one chord at a time.

| Key              | Action                                                                                            |
|------------------|---------------------------------------------------------------------------------------------------|
| Ctrl+1..5        | Switch view mode (smart grid / grid / scroll / filmstrip / single); repeat to cycle zoom submodes |
| +/-              | Zoom in / out                                                                                     |
| 0                | Reset zoom to 1x                                                                                  |
| Left/Right       | Previous / next frame (single-view mode; ignored in other modes)                                  |
| Ctrl+Left/Right  | Previous / next frame (alias of bare Left/Right)                                                  |
| PageUp/Down      | Previous / next video file in directory                                                           |
| Space            | Next video file in directory                                                                      |
| Backspace        | Previous video file in directory                                                                  |
| Z                | Previous video file in directory                                                                  |
| Ctrl+Up/Down     | Increase / decrease frame count                                                                   |
| Ctrl+A           | Select all                                                                                        |
| Ctrl+Click       | Toggle frame selection                                                                            |
| Ctrl+S           | Save frame (the focused or right-clicked one)                                                     |
| Ctrl+Shift+S     | Save view — honours the persisted *Save at view resolution* setting                               |
| Ctrl+Shift+L     | Save view at view resolution (one-shot; ignores the setting for this action only)                 |
| Ctrl+Shift+N     | Save view at native size (one-shot)                                                               |
| Ctrl+Alt+Shift+S | Save frames (selected if any are selected, otherwise all loaded frames)                           |
| Ctrl+C           | Copy frame to clipboard                                                                           |
| Ctrl+Shift+C     | Copy view — honours the persisted *Copy at view resolution* setting                               |
| Ctrl+Alt+L       | Copy view at view resolution (one-shot)                                                           |
| Ctrl+Alt+N       | Copy view at native size (one-shot)                                                               |
| Enter            | Open the current file in the OS default player                                                    |
| F11              | Toggle Lister maximize                                                                            |
| Alt+Enter        | Toggle Lister full-screen (maximize without the window caption)                                   |
| T                | Toggle timecodes                                                                                  |
| R                | Refresh (re-extract all frames)                                                                   |
| Ctrl+R           | Shuffle (pick fresh random frame positions and re-extract)                                        |
| ~                | Open hamburger menu (when toolbar is collapsed)                                                   |
| F2               | Settings                                                                                          |
| F3               | Toggle status bar                                                                                 |
| F4               | Toggle toolbar                                                                                    |
| Escape           | Close Lister                                                                                      |

### Configuration

All settings are stored in `Glimpse.ini` in the plugin directory. Access the settings dialog with F2 or via the right-click context menu. The dialog is organized into eight tabs: **General**, **Sampling**, **Appearance**, **Save**, **Cache**, **Thumbnails**, **Quick View**, **Hotkeys**. Press **Apply** to commit changes to the open viewer without closing the dialog, making the live view act as a preview. **Apply cannot be rolled back with Cancel.**

#### General

| Setting                           | Default     | Description                                                                                                                                                                     |
|-----------------------------------|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Max workers                       | 1           | Number of parallel ffmpeg processes for frame extraction. More workers = faster loading, higher CPU usage                                                                       |
| One per frame                     | Off         | Launches a separate worker for each frame instead of using a fixed worker count                                                                                                 |
| Limit workers count               | No limit    | When "One per frame" is active, caps the total number of simultaneous workers. 0 = auto (matches CPU core count)                                                                |
| Use BMP pipe                      | On          | Transfers frames via BMP pipe instead of temporary PNG files. Faster but uses more memory                                                                                       |
| Use hardware-accelerated decoding | On          | Offloads video decoding to GPU when available (DXVA2, NVDEC, QuickSync). Falls back to software decoding silently                                                               |
| Use keyframes                     | Off         | Seeks to the nearest keyframe instead of decoding to the exact timestamp. Faster but timecodes may be less precise                                                              |
| Extract frames at display size    | Off         | Asks ffmpeg to produce frames already scaled to display size instead of full resolution. Significantly faster for 4K+                                                           |
| Scale target min (px)             | 120         | Lower bound on the scale target (bigger side). Prevents the viewport-derived target from collapsing too small                                                                   |
| Scale target max (px)             | 1920        | Upper bound on the scale target (bigger side). Frames are left at native resolution when the target exceeds it                                                                  |
| Re-extract on viewport change     | On          | Quietly re-extracts in the background when switching view modes or resizing Lister so frames stay at display resolution. No effect when *Extract frames at display size* is off |
| Respect anamorphic dimensions     | On          | Scales frames to display dimensions for sources where stored pixels are non-square (DVD rips, broadcast, some cameras).                                                         |
| Extensions                        | mp4,mkv,... | Comma-separated list of video file extensions the plugin will handle                                                                                                            |
| FFmpeg path                       | Auto-detect | Explicit path to `ffmpeg.exe`. Leave empty to auto-detect from plugin directory or system PATH                                                                                  |

#### Sampling

Controls *which* moments of the video are turned into frames — independent of the engine knobs on the General tab.

| Setting                     | Default | Description                                                                                                                                                            |
|-----------------------------|---------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Skip edges                  | 2%      | Percentage of video duration to skip at the beginning and end, avoiding black intros/outros                                                                            |
| Start from random positions | Off     | When on, opening a file picks frame offsets at random within their slices instead of the deterministic midpoints.                                                      |
| Randomness                  | 50%     | Strength of the per-slice jitter window. 1% nudges the offset slightly off-centre; 100% lets a frame be picked anywhere within its slice.                              |
| Cache random frames         | Off     | When off, random extractions read from the cache (so a previously-cached random pick still hits) but do not write fresh picks back, keeping every Shuffle truly fresh. |
|                             |         | When on, random picks are cached just like normal ones                                                                                                                 |

The toolbar **Refresh** button is a split button: clicking it re-extracts the current offsets, while its dropdown arrow exposes a **Shuffle** item (Ctrl+R) that re-rolls the offsets and re-extracts. Shuffle works regardless of the *Start from random positions* checkbox — that toggle only governs the default behaviour when opening a file.

#### Appearance

| Setting                                       | Default       | Description                                                                                                                   |
|-----------------------------------------------|---------------|-------------------------------------------------------------------------------------------------------------------------------|
| Background                                    | Dark grey     | Background color behind the frame grid                                                                                        |
| Timecode bg                                   | Dark grey     | Background color of the timecode overlay on each frame                                                                        |
| Timecode opacity                              | 180           | Opacity of the timecode background (0 = fully transparent, 255 = fully opaque)                                                |
| Timestamp font                                | Segoe UI, 8pt | Font face and size for timecode labels on frames                                                                              |
| Cell gap (px)                                 | 0             | Spacing in pixels between frame cells in the viewer (0-20)                                                                    |
| Border (px)                                   | 0             | Outer margin around the grid, shared by the viewer and Save view exports (0-200)                                              |
| Timestamp corner                              | Bottom left   | Corner of each cell where the timecode label is drawn                                                                         |
| Show toolbar                                  | On            | Display the toolbar at the top of the lister window (F4 to toggle)                                                            |
| Show status bar                               | On            | Display the status bar at the bottom of the lister window (F3 to toggle)                                                      |
| Progress bar layout                           | Auto          | Where the extraction progress bar sits in the status bar.                                                                     |
| Status bar template                           | (see below)   | Token string controlling which panels appear in the status bar and in what order                                              |
| Status bar font                               | Tahoma, 9pt   | Font face and size for the status bar; the bar's height adapts to the metrics                                                 |
| Status bar height (px)                        | 0 (auto)      | Overrides the font-derived height with an explicit pixel count (logical pixels, scaled to monitor DPI). Values below the font minimum are silently bumped so text never clips. 0 = auto |
| Apply in (height)                             | Both          | In which window mode the explicit height takes effect: *Lister only*, *Quick View only*, or *Both*. The other mode falls back to auto height regardless of the px value |
| Recalculate auto-width panels on every update | On            | When on, auto-width panels re-measure to live text on every refresh; when off, they size once to a worst-case sample and lock |

##### Status bar template

The status bar is built from a token string in which every `%name%` becomes one panel, in the order written. Whitespace between tokens is ignored. Unknown identifiers render as their literal source text so typos are visible.

Default template (reproduces the panel layout used before this feature):

```
%file_position%%frame_position%%resolution%%save_dimension%%copy_dimension%%fps%%duration%%bitrate%%video_codec%%audio%%load_time align=right%
```

Tokens:

| Token              | Shows                                                                            |
|--------------------|----------------------------------------------------------------------------------|
| `%file_position%`  | Position of the current file among supported files in the folder (e.g. `3 / 12`) |
| `%filename%`       | Current file name                                                                |
| `%frames%`         | Total number of extracted frames                                                 |
| `%frame_position%` | Current frame / total in single view; total only in other modes                  |
| `%resolution%`     | Source video resolution (e.g. `1920x1080`)                                       |
| `%fps%`            | Source frame rate                                                                |
| `%duration%`       | Source duration (`H:MM:SS`)                                                      |
| `%bitrate%`        | Source container bitrate                                                         |
| `%video_codec%`    | Source video codec                                                               |
| `%audio%`          | First audio stream summary, or `No audio`                                        |
| `%load_time%`      | Time spent extracting the displayed frames (after extraction)                    |
| `%save_dimension%` | Predicted Save view output dimensions                                            |
| `%copy_dimension%` | Predicted Copy view output dimensions                                            |
| `%view_mode%`      | Active view mode (`Smart Grid`, `Grid`, `Scroll`, `Filmstrip`, `Single`)         |
| `%zoom%`           | Active zoom mode                                                                 |

Optional attributes inside a token (xml-style, no spaces in values):

| Attribute | Values                              | Effect                                                                                                                |
|-----------|-------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `width`   | `auto` (default) or pixels          | Forces a fixed pixel width. `auto` measures from text                                                                 |
| `align`   | `left` (default), `right`, `center` | Panel text alignment                                                                                                  |
| `cap`     | `true` (default), `false`           | `save_dimension` / `copy_dimension` only: shows the post-cap `WxH -> CxC` form when CombinedMaxSide shrinks the image |

A token whose identifier is fully uppercase (e.g. `%VIEW_MODE%`) uppercases its rendered text. Mixed-case identifiers (e.g. `%Resolution%`) leave the text as-is.

When a token's data is unavailable:

- `width=auto` panels collapse out of the bar (matches the legacy "no panel for missing data" behaviour).
- Fixed `width=N` panels stay at their slot and show `?` so the layout doesn't shift unexpectedly.

The `%save_dimension%` and `%copy_dimension%` panels are interactive: **double-click** flips the corresponding *Save at view resolution* / *Copy at view resolution* default (same setting the dropdown radio bullet tracks). The hand cursor on hover and the panel's tooltip surface the affordance. **Ctrl+Click** on any panel copies its text to the clipboard.

The **Stretch auto-width panels to fill the bar** setting (Appearance tab, off by default) makes the renderer distribute any remaining bar width across the auto-width panels proportionally to their natural widths — useful when you want a justified bar with no trailing gap. Fixed `width=N` panels keep their widths.

The progress bar continues to live outside the template — its position relative to the panels is governed by the *Progress bar layout* setting.

#### Save

| Setting                               | Default | Description                                                                                                                                                                                             |
|---------------------------------------|---------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Format                                | PNG     | Image format for saved frames (PNG or JPEG)                                                                                                                                                             |
| JPEG quality                          | 90      | Compression quality for JPEG output (1-100, higher = better quality, larger file)                                                                                                                       |
| PNG compression                       | 6       | Compression level for PNG output (0-9, higher = smaller file, slower save)                                                                                                                              |
| Background opacity                    | 255     | Opacity of cell gaps, border, and Copy/Save view output background (0 = fully transparent, 255 = fully opaque). PNG only; ignored for JPEG.                                                             |
| Default folder                        | (empty) | Default destination folder for saved frames. Empty = prompt every time                                                                                                                                  |
| Include file info banner              | Off     | Adds a header with video file name, resolution, and duration to Save view exports                                                                                                                       |
| Save at view resolution               | Off     | When on, saves match the on-screen layout at panel pixel size; when off, output uses native frame resolution. Also available as a checkbox in the file save dialog (Vista+).                            |
| Max combined side (px)                | 0       | Cap on the longer side of the rendered Save view / Copy view image. The combined image (with optional banner) is shrunk proportionally if its longer side exceeds this many pixels. 0 disables the cap. |
| Copy to clipboard as a file reference | Off     | Writes the image to a temp PNG in `%TEMP%` and publishes its path as `CF_HDROP` instead of a bitmap.                                                                                                    |

The toolbar **Save view** button is a split button: clicking it honors the *Save at view resolution* setting, while its dropdown arrow exposes one-shot **Save view at view resolution...** and **Save view at native size...** items that override the setting for that single action without persisting. On legacy Windows (XP / Server 2003) the dropdown is reached via right-click on the same button (the system dropdown arrow is unavailable there); right-click also works on Vista+ as an alternate access path.

The toolbar **Copy view** button works the same way: a split button whose dropdown exposes one-shot **Copy view at view resolution** and **Copy view at native size** items. The native-size variant re-extracts at native resolution before publishing to the clipboard, so the clipboard receives true native-resolution pixels rather than the viewport-scaled live cells. The default Copy view click honors the same persisted *Save at view resolution* setting that Save view uses (the setting governs both surfaces).

#### Cache

| Setting           | Default              | Description                                                                                     |
|-------------------|----------------------|-------------------------------------------------------------------------------------------------|
| Enable disk cache | On                   | Caches extracted frames on disk so re-opening the same video loads instantly                    |
| Folder            | %TEMP%\Glimpse\cache | Directory for cached frame files. Supports environment variables                                |
| Max size          | 500 MB               | Maximum total size of the cache directory. Oldest entries are evicted when the limit is reached |

#### Thumbnails

Controls the small preview icons that Total Commander shows for video files in its file panel (when thumbnail view is enabled in TC).

| Setting                        | Default | Description                                                                                                            |
|--------------------------------|---------|------------------------------------------------------------------------------------------------------------------------|
| Enable thumbnails for TC panel | On      | Provides thumbnails to TC via the WLX `ListGetPreviewBitmap` API. Disable to let TC fall back to its built-in handler  |
| Mode                           | Single  | `Single frame` extracts one representative frame; `Grid` produces a small composite of multiple frames                 |
| Position                       | 50%     | (Single mode) Position of the captured frame within the video duration (0% = first frame, 100% = last frame)           |
| Grid frames                    | 4       | (Grid mode) Number of frames laid out in the composite thumbnail (2-16)                                                |

#### Quick View

These settings only apply when the plugin is opened in TC's Quick View panel (Ctrl+Q), allowing a more compact layout that doesn't compete with the file panel for keyboard focus.

| Setting                          | Default | Description                                                                                                                  |
|----------------------------------|---------|------------------------------------------------------------------------------------------------------------------------------|
| Disable internal file navigation | On      | Prevents the arrow keys from advancing to neighbor video files, leaving them to TC's file panel where they're usually wanted |
| Hide toolbar                     | On      | Hides the toolbar in Quick View mode regardless of the Appearance setting                                                    |
| Hide status bar                  | On      | Hides the status bar in Quick View mode regardless of the Appearance setting                                                 |

#### Hotkeys

Every command-style action in the plugin is configurable. Each action can carry any number of chords — "Previous frame", for example, ships with both `Left` and `Ctrl+Left` bound, and you can add more (or remove either).

- Select a row in the list and press **Assign…** (or double-click the row) to open the shortcut editor. Press a key combination to add it; select a chord and press **Remove** to delete it. Numpad digits and `+`/`-`/`.` aliases collapse onto their top-row counterparts, so binding `0` covers `Numpad 0` automatically.
- **Clear** wipes every chord assigned to the selected action.
- **Reset all** restores every action to its default binding.
- Conflicts are resolved at assignment time: when you add a chord that another action already owns, the editor asks whether to reassign. Saying yes silently strips the chord from the previous owner.
- Tab, Alt+F4, and bare modifier keys are not user-configurable — they belong to VCL focus cycling and the Windows window-management shell.

When the plugin holds keyboard focus, all other key combinations are owned by this table, regardless of Lister's built-in defaults. An unbound action simply does nothing; Lister's original shortcuts (Escape to close, `1`..`9` to switch text/binary/hex views, etc.) are still available via Lister's menu.

#### Diagnostics

There is no UI control for debug logging — the toggle is hand-edited in the WLX `Glimpse.ini`:

```ini
[debug]
LogEnabled=1
```

When enabled, the plugin writes to `glimpse_debug.log` next to the WLX DLL. The file is wiped at each Total Commander startup (when logging is on), so a single repro session lives in one self-contained file. The setting takes effect on the next TC startup. Set back to `0` (or remove the line) to stop logging. Debug builds default to logging on; release builds default to off — the explicit INI value always wins.

## WCX Plugin (Packer)

Presents a video file as a virtual archive containing frame images. Opening a video in TC shows files like `video_frame_001_00m05s.png` that can be copied, viewed, or batch-extracted using standard TC operations.

### Use Cases

- Batch-extract thumbnails from many videos at once using TC's multi-file copy
- Preview frame filenames before extracting
- Use TC's built-in viewer to browse individual frames
- Run user-defined ffmpeg presets (audio rip, low-bitrate preview, custom transcodes) by extracting them from the virtual archive — see [Presets](#presets)

### Configuration

Open the settings dialog via Files > Pack (Alt+F5) > Configure. The WCX plugin uses its own `Glimpse.ini`, separate from the WLX plugin. After changing settings, re-enter the video file to see the updated listing. The dialog is organized into six tabs: **General**, **Sampling**, **Output**, **Combined**, **Presets**, **Size limit**.

#### General

| Setting                           | Default     | Description                                                                                                             |
|-----------------------------------|-------------|-------------------------------------------------------------------------------------------------------------------------|
| Max workers                       | 1           | Number of parallel ffmpeg processes for frame extraction                                                                |
| One per frame                     | Off         | Launches a separate worker for each frame                                                                               |
| Limit workers count               | No limit    | When "One per frame" is active, caps the total number of simultaneous workers                                           |
| Use BMP pipe                      | On          | Transfers frames via BMP pipe instead of temporary files                                                                |
| Use hardware-accelerated decoding | On          | Offloads video decoding to GPU when available. Falls back to software silently                                          |
| Use keyframes                     | Off         | Seeks to the nearest keyframe instead of exact timestamp. Faster seeking                                                |
| Respect anamorphic dimensions     | On          | Scales frames to display dimensions for sources where stored pixels are non-square (DVD rips, broadcast, some cameras). |
| FFmpeg path                       | Auto-detect | Explicit path to `ffmpeg.exe`. Leave empty to auto-detect                                                               |

#### Sampling

Controls *which* moments of the video are extracted. Re-enter the archive to see picks change.

| Setting                     | Default | Description                                                                                                                      |
|-----------------------------|---------|----------------------------------------------------------------------------------------------------------------------------------|
| Frame count                 | 4       | Number of frames to extract from the video (1-99)                                                                                |
| Skip edges                  | 2%      | Percentage of video duration to skip at the beginning and end                                                                    |
| Start from random positions | Off     | When on, each TC entry into the archive picks frame offsets at random within their slices instead of the deterministic midpoints |
| Randomness                  | 50%     | Strength of the per-slice jitter window. 1% = slight nudge off-centre, 100% = anywhere within the slice.                         |
|                             |         | No effect when *Start from random positions* is off                                                                              |

WCX has no "Cache random frames" toggle: the plugin runs on demand from TC and has no frame cache, so the option would be a no-op.

#### Output

| Setting            | Default     | Description                                                                                                                                                                          |
|--------------------|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Listing modes      | Frames only | Three independent toggles compose the archive listing:<br/>- **Frames** (individual images)<br/>- **Combined** (single grid image),<br/>- **Presets** (user-defined ffmpeg recipes). |
| Image format       | PNG         | Image format for extracted frames (PNG or JPEG)                                                                                                                                      |
| JPEG quality       | 90          | Compression quality for JPEG output (1-100)                                                                                                                                          |
| PNG compression    | 6           | Compression level for PNG output (0-9)                                                                                                                                               |
| Background opacity | 255         | Opacity of cell gaps, border, and combined-image background (0 = fully transparent, 255 = fully opaque). PNG only; ignored for JPEG.                                                 |
| Show file sizes    | Off         | Displays actual file sizes in the archive listing. Requires extracting all frames when entering the archive                                                                          |

#### Combined

These settings only apply when output mode is set to "Combined image":

| Setting                  | Default       | Description                                                              |
|--------------------------|---------------|--------------------------------------------------------------------------|
| Columns                  | 0 (auto)      | Number of columns in the grid. 0 = automatic layout based on frame count |
| Cell gap (px)            | 2             | Spacing in pixels between frames in the grid                             |
| Background               | Dark grey     | Background color visible in cell gaps and margins                        |
| Show timestamps          | On            | Overlays timecode labels on each frame                                   |
| Timestamp font           | Consolas, 9pt | Font face and size for timecode labels                                   |
| Include file info banner | Off           | Adds a header with video file name, resolution, and duration             |

#### Presets

User-defined ffmpeg recipes that appear as additional virtual files in the archive listing alongside (or instead of) the frame and combined entries. Each preset is a complete ffmpeg invocation — extract a preset entry and the plugin runs ffmpeg with your arguments and saves the result to TC's chosen destination.

Enable preset listing by ticking the **Presets** checkbox in the Output tab. Disabled presets remain visible in the editor (so you can re-enable them) but do not appear in the archive listing.

The Presets tab provides a master-detail editor: the list on the left shows every preset, the panel on the right edits the currently selected one. **Add** creates a blank preset, **Del** removes the selection, **Copy** duplicates with a fresh name. Saved on Apply or OK.

| Field       | Description                                                                                                                                                                                                                                                                                                                            |
|-------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Name        | INI section name; doubles as the `%name%` template variable. Must be unique (case-insensitive)                                                                                                                                                                                                                                         |
| Enabled     | When off, the preset is hidden from the archive listing but kept in the editor                                                                                                                                                                                                                                                         |
| Description | Free-text label, shown only in the editor                                                                                                                                                                                                                                                                                              |
| Output ext  | File extension without the leading dot (e.g. `mp3`, `jpg`). Required. ffmpeg picks the muxer/encoder from this when no explicit codec is given                                                                                                                                                                                         |
| Output name | Filename template. Defaults to `%basename%_%name%`. Recognised variables: `%basename%` (source filename without path or extension), `%name%` (preset section name), `%ext%` (source extension, lowercased, no dot). Unknown `%token%` patterns pass through verbatim. May contain `/` or `\` for virtual subfolders inside the archive |
| ffmpeg args | Arguments inserted between `-i <input>` and the output file. The same template variables as Output name expand here too (e.g. `-metadata title=%basename%`). Forbidden tokens (rejected at save): `-i`, `-y`, `-n`, `pipe:0`, `pipe:1`, `pipe:2`. May be empty, in which case ffmpeg picks default codecs from the output extension    |

Presets live in `presets.ini` next to `Glimpse.ini`. The file is hand-editable — each preset is a `[name]` section with `OutputExt=`, `Args=`, etc. The editor reads and writes this file; manual edits are picked up on the next archive open. The file is UTF-8 (with or without BOM); modern editors save it correctly.

When a preset extraction fails, ffmpeg's actual error appears in a dialog ("Glimpse preset extraction failed") with the relevant ffmpeg stderr line — useful for debugging your args.

Naming collisions between presets get the standard `(N)` suffix in the listing; first-defined wins the bare name. Place a preset under a virtual subfolder (e.g. `OutputName=audio/%basename%`) to avoid collisions and group related presets visually.

#### Size limit

Caps the longer side of extracted output in pixels (the cap applies to whichever side is longer, regardless of orientation). Useful for keeping batch-extracted thumbnails compact.

| Setting                     | Default      | Description                                                                                                                |
|-----------------------------|--------------|----------------------------------------------------------------------------------------------------------------------------|
| Separate frames longer side | 0 (no limit) | When `Separate frames` mode is active, ffmpeg downscales each frame so its longer side does not exceed this many pixels    |
| Combined image longer side  | 0 (no limit) | When `Combined image` mode is active, the assembled grid is downscaled so its longer side does not exceed this many pixels |

#### Diagnostics

There is no UI control for debug logging — the toggle is hand-edited in `Glimpse.ini`:

```ini
[debug]
LogEnabled=1
```

When enabled, the plugin writes to `Glimpse.log` next to the WCX DLL. Lines are tagged `WCX:` for general operations and `WCX-Presets:` for preset loader warnings (rejected presets, malformed values). The setting takes effect on the next archive open — no TC restart required. Set back to `0` (or remove the line) and reopen any archive to stop logging. The existing log file is left in place for inspection.

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
