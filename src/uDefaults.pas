{ Shared default values and clamping ranges for extraction and output settings.
  Used by both WLX and WCX plugins to ensure consistent behavior. }
unit uDefaults;

interface

uses
  uBitmapSaver;

const
  { Extraction defaults }
  DEF_FRAMES_COUNT    = 4;
  DEF_SKIP_EDGES      = 2;
  DEF_MAX_WORKERS     = 1;
  DEF_MAX_THREADS     = -1;  { -1 = no limit, 0 = auto (CPU count) }
  DEF_USE_BMP_PIPE    = True;

  { Output format defaults }
  DEF_SAVE_FORMAT     = sfPNG;
  DEF_JPEG_QUALITY    = 90;
  DEF_PNG_COMPRESSION = 6;

  { Extension list }
  DEF_EXTENSION_LIST  = 'mp4,mkv,avi,mov,wmv,webm,flv,ts,m2ts,m4v,3gp,ogv,mpg,mpeg,vob,asf,rm,rmvb,f4v';

  { Clamping ranges }
  MIN_FRAMES_COUNT    = 1;
  MAX_FRAMES_COUNT    = 99;
  MIN_SKIP_EDGES      = 0;
  MAX_SKIP_EDGES      = 49;
  MIN_MAX_WORKERS     = 0;
  MAX_MAX_WORKERS     = 16;
  MIN_MAX_THREADS     = -1;
  MAX_MAX_THREADS     = 64;
  MIN_JPEG_QUALITY    = 1;
  MAX_JPEG_QUALITY    = 100;
  MIN_PNG_COMPRESSION = 0;
  MAX_PNG_COMPRESSION = 9;

implementation

end.
