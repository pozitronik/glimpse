{Shared default values and clamping ranges for extraction and output settings.
 Used by both WLX and WCX plugins to ensure consistent behavior.}
unit uDefaults;

interface

uses
  System.UITypes,
  uBitmapSaver, uTypes;

const
  {Extraction defaults}
  DEF_FRAMES_COUNT = 4;
  DEF_SKIP_EDGES = 2;
  DEF_MAX_WORKERS = 1;
  DEF_MAX_THREADS = -1; {-1 = no limit, 0 = auto (CPU count)}
  DEF_USE_BMP_PIPE = True;
  DEF_HW_ACCEL = True;
  DEF_USE_KEYFRAMES = False;
  {Background opacity for the saved combined image (PNG only). 0 = fully
   transparent gaps/border, 255 = fully opaque (existing behaviour).
   Frames themselves are always opaque regardless of this value.}
  DEF_BACKGROUND_ALPHA = 255;
  MIN_BACKGROUND_ALPHA = 0;
  MAX_BACKGROUND_ALPHA = 255;
  {Default to ON: most users expect saved frames to look like the source
   in a player. Anamorphic content is a minority but the cost of
   "iw*sar:ih" on square-pixel sources is zero.}
  DEF_RESPECT_ANAMORPHIC = True;
  DEF_SCALED_EXTRACTION = False;
  DEF_MIN_FRAME_SIDE = 120;
  DEF_MAX_FRAME_SIDE = 1920;

  {Random extraction. When enabled, opening a file picks frame offsets
   at random within their slices instead of slice midpoints. Slider
   controls jitter magnitude; same value drives the on-demand Shuffle
   action (paShuffleExtraction). CacheRandomFrames toggles whether
   random extractions write to the disk cache (reads always go through
   so previously-cached picks can still hit).
   Defaults: feature off, mid-strength jitter, no cache writes — matches
   the mental model "random means random" while preserving the existing
   user experience for everyone who never touches the slider.}
  DEF_RANDOM_EXTRACTION = False;
  DEF_RANDOM_PERCENT = 50;
  DEF_CACHE_RANDOM_FRAMES = False;
  MIN_RANDOM_PERCENT = 1;
  MAX_RANDOM_PERCENT = 100;
  {When the viewport changes (view mode switch, Lister window resize) and
   ScaledExtraction would pick a different MaxSide, re-extract in the
   background so the visible frames stay at display resolution.}
  DEF_AUTO_REFRESH_VIEWPORT = True;

  {Output format defaults}
  DEF_SAVE_FORMAT = sfPNG;
  DEF_JPEG_QUALITY = 90;
  DEF_PNG_COMPRESSION = 6;

  {When True, file save renders the output at the size the live view
   currently shows on screen (cell pixel dimensions taken from the
   layout). When False, output uses native frame resolution.
   Default False to preserve the long-standing "frame-resolution combined
   image" behaviour for users who do not opt in.

   Sister setting DEF_COPY_AT_LIVE_RESOLUTION governs the clipboard path
   independently; see comment below.}
  DEF_SAVE_AT_LIVE_RESOLUTION = False;

  {Same idea as DEF_SAVE_AT_LIVE_RESOLUTION but for clipboard copies.
   Split out so users can have e.g. native-resolution file saves and
   smaller view-resolution clipboard copies (typical "save the full
   thing, paste a thumbnail into a chat" workflow). Default False
   matches the historical pre-split behaviour where a single setting
   drove both surfaces.}
  DEF_COPY_AT_LIVE_RESOLUTION = False;

  {Cap on the longer side (in pixels) of the rendered combined image
   produced by Save view / Copy view. After the combined image (with
   optional banner) is rendered, if its longer side exceeds this value,
   the bitmap is shrunk proportionally to fit. 0 disables the cap.
   Default 0 (unlimited) preserves the historical "save at full native
   resolution" behaviour for users who do not opt in; users hitting
   clipboard OOM or huge save files can dial in a cap (8192 is a good
   starting point on a 32-bit build).
   Mirrors WCX_DEF_COMBINED_MAX_SIDE in WCX (same default; the plugins
   keep separate values but share the property name to make the shared
   concept obvious).}
  DEF_COMBINED_MAX_SIDE = 0;
  MIN_COMBINED_MAX_SIDE = 0;
  MAX_COMBINED_MAX_SIDE = 32768;

  {Extension list}
  DEF_EXTENSION_LIST = 'mp4,mkv,avi,mov,wmv,webm,flv,ts,m2ts,m4v,3gp,ogv,mpg,mpeg,vob,asf,rm,rmvb,f4v';

  {Timestamp font size range (shared by both plugins)}
  MIN_TIMESTAMP_FONT_SIZE = 6;
  MAX_TIMESTAMP_FONT_SIZE = 72;

  {Timestamp font defaults used by WLX. WCX overrides to its own pair
   (WCX_DEF_TIMESTAMP_FONT/SIZE) in uWcxSettings. Kept here so the shared
   settings-group records in uSettingsGroups can seed sensible fallbacks
   without creating a circular dependency on uSettings.}
  DEF_TIMESTAMP_FONT = 'Segoe UI';
  DEF_TIMESTAMP_FONT_SIZE = 8;

  {Timestamp text opacity (0 = invisible, 255 = fully opaque). Shared by both plugins.}
  DEF_TIMESTAMP_TEXT_ALPHA = 255;
  MIN_TIMESTAMP_TEXT_ALPHA = 0;
  MAX_TIMESTAMP_TEXT_ALPHA = 255;

  {Timestamp text color on loaded cells (pending cells are auto-dimmed at render time).
   Matches the historical CLR_TIMECODE_OVERLAY shade so legacy configs look identical.}
  DEF_TIMESTAMP_TEXT_COLOR = TColor($00CCCCCC);

  {Timecode background block (shared by WLX live view and WCX combined image).}
  DEF_TC_BACK_COLOR = TColor($002D2D2D);
  DEF_TC_BACK_ALPHA = 180;

  {Cell gap floor (shared by both plugins: WLX viewer and WCX combined image).
   No upper cap: negative pixel sizes are nonsense, but huge values are the
   user's choice.}
  MIN_CELL_GAP = 0;

  {Outer border (margin) around the whole grid. Shared by WLX live view and combined image.}
  DEF_COMBINED_BORDER = 0;
  MIN_COMBINED_BORDER = 0;

  {Default timestamp corner for both WLX cells and combined image cells.}
  DEF_TIMESTAMP_CORNER = tcBottomLeft;

  {Info banner defaults (shared by WLX exports and WCX combined output).
   Auto-size uses the image-width-based heuristic; when off, BannerFontSize
   drives the banner text size in points.}
  DEF_BANNER_BACKGROUND = TColor($00282828);
  DEF_BANNER_TEXT_COLOR = TColor($00E0E0E0);
  DEF_BANNER_FONT_NAME = 'Segoe UI';
  DEF_BANNER_FONT_SIZE = 10;
  DEF_BANNER_FONT_AUTO_SIZE = True;
  DEF_BANNER_POSITION = bpTop;
  MIN_BANNER_FONT_SIZE = 6;
  MAX_BANNER_FONT_SIZE = 72;

  {Clamping ranges}
  MIN_FRAMES_COUNT = 1;
  MAX_FRAMES_COUNT = 99;
  MIN_SKIP_EDGES = 0;
  MAX_SKIP_EDGES = 49;
  MIN_MAX_WORKERS = 0;
  MAX_MAX_WORKERS = 16;
  MIN_MAX_THREADS = -1;
  MAX_MAX_THREADS = 64;
  MIN_FRAME_SIDE = 32;
  MAX_FRAME_SIDE = 7680; {8K}
  SCALE_BUCKET = 160; {resolution bucket step for cache key stability}
  MIN_JPEG_QUALITY = 1;
  MAX_JPEG_QUALITY = 100;
  MIN_PNG_COMPRESSION = 0;
  MAX_PNG_COMPRESSION = 9;

  {Thumbnail (TC panel preview) defaults}
  DEF_THUMBNAILS_ENABLED = True;
  DEF_THUMBNAIL_MODE = tnmSingle;
  {Position 0.0 = first frame, 0.5 = middle, 1.0 = last frame.
   Stored as integer percent in INI for human readability.}
  DEF_THUMBNAIL_POSITION = 50;
  DEF_THUMBNAIL_GRID_FRAMES = 4;
  {Hard cap on a single ffmpeg call from the thumbnail path so a broken
   file cannot stall the TC thumbnail worker thread indefinitely.}
  DEF_THUMBNAIL_TIMEOUT_MS = 5000;

  MIN_THUMBNAIL_POSITION = 0;
  MAX_THUMBNAIL_POSITION = 100;
  MIN_THUMBNAIL_GRID_FRAMES = 2;
  MAX_THUMBNAIL_GRID_FRAMES = 16;

  {Status bar template defaults. Reproduces the panel order the WLX bar
   used before the template engine landed: file position, frame
   position, source resolution, predicted Save / Copy view dimensions,
   fps, duration, bitrate, video codec, audio summary, load time. Every
   token defaults to width=auto so the panel collapses out cleanly when
   its datum is unavailable (matches the legacy "no panel for missing
   data" behaviour). load_time is right-justified to mirror the legacy
   layout. Tokens %view_mode%, %zoom%, %filename% and %frames% are not
   in the default but remain available for users to add.}
  DEF_STATUSBAR_TEMPLATE =
    '%file_position%' +
    '%frame_position%' +
    '%resolution%' +
    '%save_dimension%' +
    '%copy_dimension%' +
    '%fps%' +
    '%duration%' +
    '%bitrate%' +
    '%video_codec%' +
    '%audio%' +
    '%load_time align=right%';

  {Status bar font defaults — match the pre-template hardcoded values
   (Tahoma is the system default for TStatusBar.Font.Name; size 9 was
   the explicit STATUSBAR_FONT constant in uPluginForm).}
  DEF_STATUSBAR_FONT_NAME = 'Tahoma';
  DEF_STATUSBAR_FONT_SIZE = 9;
  MIN_STATUSBAR_FONT_SIZE = 6;
  MAX_STATUSBAR_FONT_SIZE = 24;

  {Off by default: auto-width panels measure their representative sample
   text once at template / font apply time and lock the width. Avoids
   the layout shift that would happen if the bar re-measured live text
   on every Refresh. Power users with stable terminal-style layouts can
   opt in via the settings dialog.}
  DEF_STATUSBAR_AUTO_WIDTH_LIVE = False;

implementation

end.
