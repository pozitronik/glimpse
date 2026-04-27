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
  {When the viewport changes (view mode switch, Lister window resize) and
   ScaledExtraction would pick a different MaxSide, re-extract in the
   background so the visible frames stay at display resolution.}
  DEF_AUTO_REFRESH_VIEWPORT = True;

  {Output format defaults}
  DEF_SAVE_FORMAT = sfPNG;
  DEF_JPEG_QUALITY = 90;
  DEF_PNG_COMPRESSION = 6;

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

implementation

end.
