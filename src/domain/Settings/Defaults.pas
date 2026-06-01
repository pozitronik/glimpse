{Shared default values and clamping ranges. Used by both WLX and WCX.}
unit Defaults;

interface

uses
  System.UITypes,
  BitmapSaver, Types, StatusBarLayout, ClipboardTemp;

const
  {Extraction defaults}
  DEF_FRAMES_COUNT = 4;
  DEF_SKIP_EDGES = 2;
  DEF_MAX_WORKERS = 1;
  DEF_MAX_THREADS = -1; {-1 = no limit, 0 = auto (CPU count)}
  DEF_USE_BMP_PIPE = True;
  DEF_HW_ACCEL = True;
  DEF_USE_KEYFRAMES = False;
  {Saved combined image gap/border opacity (PNG only). Frames stay opaque.}
  DEF_BACKGROUND_ALPHA = 255;
  MIN_BACKGROUND_ALPHA = 0;
  MAX_BACKGROUND_ALPHA = 255;
  DEF_RESPECT_ANAMORPHIC = True;
  DEF_SCALED_EXTRACTION = False;
  DEF_MIN_FRAME_SIDE = 120;
  DEF_MAX_FRAME_SIDE = 1920;

  {CacheRandomFrames=False so random picks never pollute the cache; reads
   still hit previously-cached entries.}
  DEF_RANDOM_EXTRACTION = False;
  DEF_RANDOM_PERCENT = 50;
  DEF_CACHE_RANDOM_FRAMES = False;
  MIN_RANDOM_PERCENT = 1;
  MAX_RANDOM_PERCENT = 100;
  DEF_AUTO_REFRESH_VIEWPORT = True;

  {Output format defaults}
  DEF_SAVE_FORMAT = sfPNG;
  DEF_JPEG_QUALITY = 90;
  DEF_PNG_COMPRESSION = 6;

  {Clipboard publishing knobs. JpegQuality and PngCompression apply to both
   the direct-publish clipboard strategies (registered PNG / JFIF formats)
   and the file-reference temp encoder. FileReferenceFormat and
   FileReferenceBackgroundAlpha govern only the file-reference temp file —
   the direct-publish strategies pick format by per-format toggle and use
   the global render background for compositing where needed.}
  DEF_CLIPBOARD_FILE_REFERENCE_FORMAT = sfPNG;
  DEF_CLIPBOARD_JPEG_QUALITY = DEF_JPEG_QUALITY;
  DEF_CLIPBOARD_PNG_COMPRESSION = DEF_PNG_COMPRESSION;
  DEF_CLIPBOARD_FILE_REFERENCE_BACKGROUND_ALPHA = DEF_BACKGROUND_ALPHA;

  DEF_SAVE_AT_LIVE_RESOLUTION = False;
  DEF_COPY_AT_LIVE_RESOLUTION = False;

  {Workaround for 32-bit OOM with large combined images: publish CF_HDROP
   pointing at a %TEMP% PNG instead of a second in-memory bitmap copy.
   Bitmap-only paste targets (MS Paint) won't work while on.}
  DEF_CLIPBOARD_AS_FILE_REFERENCE = False;

  DEF_PUBLISH_ALPHA_AWARE_BITMAP = True; {CF_DIBV5}
  DEF_PUBLISH_FLATTENED_BITMAP = True; {CF_DIB}
  DEF_PUBLISH_BITMAP_HANDLE = True; {CF_BITMAP}
  DEF_PUBLISH_COMPRESSED_PNG = True; {registered "PNG" format}
  {Registered "JFIF" format. Default off: PNG already covers the
   compressed-publish slot, and JFIF readers are a minority. Users who want
   it opt in explicitly.}
  DEF_PUBLISH_COMPRESSED_JPEG = False;

  {Save/Copy view longer-side cap (0 = unlimited). 8192 is a good starting
   point for 32-bit clipboard OOM. Mirrors WCX_DEF_COMBINED_MAX_SIDE.}
  DEF_COMBINED_MAX_SIDE = 0;
  MIN_COMBINED_MAX_SIDE = 0;
  MAX_COMBINED_MAX_SIDE = 32768;

  {Extension list}
  DEF_EXTENSION_LIST = 'mp4,mkv,avi,mov,wmv,webm,flv,ts,m2ts,m4v,3gp,ogv,mpg,mpeg,vob,asf,rm,rmvb,f4v';

  {Timestamp font size range (shared by both plugins)}
  MIN_TIMESTAMP_FONT_SIZE = 6;
  MAX_TIMESTAMP_FONT_SIZE = 72;

  {WCX overrides via WCX_DEF_TIMESTAMP_FONT/SIZE in WcxSettings.}
  DEF_TIMESTAMP_FONT = 'Segoe UI';
  DEF_TIMESTAMP_FONT_SIZE = 8;

  {Timestamp text opacity (0 = invisible, 255 = fully opaque). Shared by both plugins.}
  DEF_TIMESTAMP_TEXT_ALPHA = 255;
  MIN_TIMESTAMP_TEXT_ALPHA = 0;
  MAX_TIMESTAMP_TEXT_ALPHA = 255;

  {Timestamp text colour on loaded cells; pending cells auto-dim.}
  DEF_TIMESTAMP_TEXT_COLOR = TColor($00CCCCCC);

  {Timecode background block (shared by WLX live view and WCX combined image).}
  DEF_TC_BACK_COLOR = TColor($002D2D2D);
  DEF_TC_BACK_ALPHA = 180;

  MIN_CELL_GAP = 0;

  DEF_COMBINED_BORDER = 0;
  MIN_COMBINED_BORDER = 0;

  DEF_TIMESTAMP_CORNER = tcBottomLeft;

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
  {Integer percent: 0=first frame, 50=middle, 100=last.}
  DEF_THUMBNAIL_POSITION = 50;
  DEF_THUMBNAIL_GRID_FRAMES = 4;
  {Cap on a single ffmpeg call so a broken file cannot stall the TC
   thumbnail worker thread indefinitely.}
  DEF_THUMBNAIL_TIMEOUT_MS = 5000;

  MIN_THUMBNAIL_POSITION = 0;
  MAX_THUMBNAIL_POSITION = 100;
  MIN_THUMBNAIL_GRID_FRAMES = 2;
  MAX_THUMBNAIL_GRID_FRAMES = 16;

  {Default panel order. Every token is width=auto so panels collapse out
   when their datum is unavailable. %view_mode% %zoom% %filename%
   %frames% are also available.}
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

  DEF_STATUSBAR_FONT_NAME = 'Tahoma';
  DEF_STATUSBAR_FONT_SIZE = 9;
  MIN_STATUSBAR_FONT_SIZE = 6;
  MAX_STATUSBAR_FONT_SIZE = 24;

  DEF_STATUSBAR_AUTO_WIDTH_LIVE = True;
  DEF_STATUSBAR_STRETCH_PANELS = False;

  {0 = auto: height derived from font's TextHeight + padding. Values
   below the font minimum are silently bumped so text never clips.
   Logical pixels; scales via MulDiv against CurrentPPI.}
  DEF_STATUSBAR_HEIGHT = 0;
  MIN_STATUSBAR_HEIGHT = 0;
  MAX_STATUSBAR_HEIGHT = 200;

  DEF_STATUSBAR_HEIGHT_APPLY_MODE = sbhamBoth;

  DEF_STATUSBAR_DIMENSION_CLICK_MODE = sbdcmDouble;

  {Clipboard file-reference temp-file management. Empty folder = the system
   %TEMP%; any other value (env vars expanded) overrides it, e.g. TC's own
   temp tree. Cleanup sweeps leftover glimpse_clip_* files on plugin load:
   default is "delete older than 24h", a grace window that still allows the
   intended paste-after-close while not hoarding files forever.}
  DEF_CLIPBOARD_TEMP_FOLDER = '';
  DEF_CLIPBOARD_CLEANUP_STRATEGY = ccsOlderThan;
  DEF_CLIPBOARD_CLEANUP_AGE_SECONDS = SECONDS_PER_DAY;
  MIN_CLIPBOARD_CLEANUP_AGE_SECONDS = 0;
  {Cap the configurable age at 365 days so a fat-fingered DD field can not
   overflow into a nonsensical span; well beyond any real grace window.}
  MAX_CLIPBOARD_CLEANUP_AGE_SECONDS = 365 * SECONDS_PER_DAY;

implementation

end.
