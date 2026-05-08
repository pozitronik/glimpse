object WcxSettingsForm: TWcxSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse WCX Settings'
  ClientHeight = 470
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  ShowHint = True
  TextHeight = 15
  object PageControl: TPageControl
    Left = 0
    Top = 0
    Width = 460
    Height = 430
    ActivePage = TshGeneral
    Align = alClient
    TabOrder = 0
    object TshGeneral: TTabSheet
      Caption = 'General'
      DesignSize = (
        452
        400)
      object LblMaxWorkers: TLabel
        Left = 12
        Top = 24
        Width = 69
        Height = 15
        Caption = 'Max workers:'
      end
      object LblMaxThreads: TLabel
        Left = 12
        Top = 53
        Width = 108
        Height = 15
        Caption = 'Limit workers count:'
      end
      object LblMaxThreadsAuto: TLabel
        Left = 198
        Top = 53
        Width = 3
        Height = 15
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object LblFFmpegPath: TLabel
        Left = 12
        Top = 202
        Width = 73
        Height = 15
        Caption = 'FFmpeg path:'
      end
      object LblFFmpegInfo: TLabel
        Left = 12
        Top = 249
        Width = 427
        Height = 15
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object EdtMaxWorkers: TEdit
        Left = 130
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '1'
      end
      object UdMaxWorkers: TUpDown
        Left = 175
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtMaxWorkers
        Min = 1
        Max = 16
        Position = 1
        TabOrder = 1
        Thousands = False
      end
      object ChkMaxWorkersAuto: TCheckBox
        Left = 198
        Top = 24
        Width = 130
        Height = 17
        Caption = 'One per frame'
        Hint = 'Spawn one ffmpeg worker per requested frame, ignoring Max workers above.'
        TabOrder = 2
        OnClick = ChkMaxWorkersAutoClick
      end
      object EdtMaxThreads: TEdit
        Left = 130
        Top = 49
        Width = 45
        Height = 23
        Hint = 'Per-worker ffmpeg thread cap. 0 = let ffmpeg decide, -1 = single-threaded.'
        NumbersOnly = True
        TabOrder = 3
        Text = '0'
        OnChange = EdtMaxThreadsChange
      end
      object UdMaxThreads: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtMaxThreads
        Hint = 'Per-worker ffmpeg thread cap. 0 = let ffmpeg decide, -1 = single-threaded.'
        Min = -1
        Max = 64
        TabOrder = 4
        Thousands = False
      end
      object ChkUseBmpPipe: TCheckBox
        Left = 12
        Top = 82
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use BMP pipe (faster extraction, higher memory usage)'
        Hint = 'Stream raw BMP from ffmpeg in memory instead of going through temporary image files.'
        TabOrder = 5
      end
      object ChkHwAccel: TCheckBox
        Left = 12
        Top = 111
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use hardware-accelerated decoding (GPU)'
        Hint = 'Asks ffmpeg to use a GPU decoder when available. Falls back to CPU if it cannot.'
        TabOrder = 6
      end
      object ChkUseKeyframes: TCheckBox
        Left = 12
        Top = 140
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use keyframes (faster seeking, less precise timecodes)'
        Hint = 'Seeks only to the nearest keyframe. Much faster, but the actual frame may differ from the requested timecode.'
        TabOrder = 7
      end
      object ChkRespectAnamorphic: TCheckBox
        Left = 12
        Top = 169
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Respect anamorphic dimensions'
        Hint = 'Uses the video'#39's display aspect ratio when sizing frames, not the raw pixel grid.'
        TabOrder = 8
      end
      object EdtFFmpegPath: TEdit
        Left = 12
        Top = 222
        Width = 396
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        Hint = 'Optional override for the ffmpeg executable path. Leave empty to auto-detect from PATH.'
        TabOrder = 9
        TextHint = 'Auto-detect'
        OnChange = EdtFFmpegPathChange
      end
      object BtnFFmpegPath: TButton
        Left = 414
        Top = 222
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        Hint = 'Browse for the ffmpeg executable.'
        TabOrder = 10
        OnClick = BtnFFmpegPathClick
      end
    end
    object TshSampling: TTabSheet
      Caption = 'Sampling'
      ImageIndex = 4
      DesignSize = (
        452
        400)
      object LblFrameCount: TLabel
        Left = 12
        Top = 24
        Width = 70
        Height = 15
        Caption = 'Frame count:'
      end
      object LblSkipEdges: TLabel
        Left = 12
        Top = 53
        Width = 59
        Height = 15
        Caption = 'Skip edges:'
      end
      object LblSkipEdgesUnit: TLabel
        Left = 198
        Top = 53
        Width = 10
        Height = 15
        Caption = '%'
      end
      object LblRandomPercent: TLabel
        Left = 12
        Top = 111
        Width = 71
        Height = 15
        Caption = 'Randomness:'
      end
      object LblRandomPercentValue: TLabel
        Left = 414
        Top = 111
        Width = 22
        Height = 15
        Anchors = [akTop, akRight]
        Caption = '50%'
      end
      object EdtFrameCount: TEdit
        Left = 130
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '1'
      end
      object UdFrameCount: TUpDown
        Left = 175
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtFrameCount
        Min = 1
        Max = 99
        Position = 1
        TabOrder = 1
        Thousands = False
      end
      object EdtSkipEdges: TEdit
        Left = 130
        Top = 49
        Width = 45
        Height = 23
        Hint = 'Excludes the first and last N% of the video when picking frame positions.'
        NumbersOnly = True
        TabOrder = 2
        Text = '0'
      end
      object UdSkipEdges: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtSkipEdges
        Max = 49
        TabOrder = 3
        Thousands = False
      end
      object ChkRandomExtraction: TCheckBox
        Left = 12
        Top = 82
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Start from random positions'
        Hint = 'Picks frame positions randomly inside the allowed range instead of evenly spacing them.'
        TabOrder = 4
        OnClick = ChkRandomExtractionClick
      end
      object TrkRandomPercent: TTrackBar
        Left = 94
        Top = 107
        Width = 314
        Height = 25
        Anchors = [akLeft, akTop, akRight]
        Hint = 'Width of the random window around each evenly-spaced position. Higher = more variance, lower = closer to even spacing.'
        Max = 100
        Min = 1
        Frequency = 5
        Position = 50
        ShowSelRange = False
        TabOrder = 5
        TickMarks = tmBoth
        OnChange = TrkRandomPercentChange
      end
    end
    object TshOutput: TTabSheet
      Caption = 'Output'
      ImageIndex = 1
      DesignSize = (
        452
        400)
      object LblOutputMode: TLabel
        Left = 12
        Top = 24
        Width = 80
        Height = 15
        Caption = 'Listing modes:'
      end
      object LblFormat: TLabel
        Left = 12
        Top = 53
        Width = 75
        Height = 15
        Caption = 'Image format:'
      end
      object LblJpegQuality: TLabel
        Left = 12
        Top = 82
        Width = 67
        Height = 15
        Caption = 'JPEG quality:'
      end
      object LblPngCompression: TLabel
        Left = 12
        Top = 111
        Width = 98
        Height = 15
        Caption = 'PNG compression:'
      end
      object LblBackgroundAlpha: TLabel
        Left = 12
        Top = 140
        Width = 109
        Height = 15
        Caption = 'Background opacity:'
      end
      object ChkModeFrames: TCheckBox
        Left = 130
        Top = 22
        Width = 90
        Height = 17
        Caption = 'Frames'
        Hint = 'List each extracted frame as a separate file in the archive.'
        TabOrder = 0
        OnClick = ChkModeFramesClick
      end
      object ChkModeCombined: TCheckBox
        Left = 222
        Top = 22
        Width = 100
        Height = 17
        Caption = 'Combined'
        Hint = 'List a single contact-sheet image combining every extracted frame.'
        TabOrder = 12
        OnClick = ChkModeCombinedClick
      end
      object ChkModePresets: TCheckBox
        Left = 324
        Top = 22
        Width = 100
        Height = 17
        Caption = 'Presets'
        Hint = 'List user-defined ffmpeg presets as additional virtual files. Configure them on the Presets tab.'
        TabOrder = 13
        OnClick = ChkModePresetsClick
      end
      object CbxFormat: TComboBox
        Left = 130
        Top = 49
        Width = 80
        Height = 23
        Style = csDropDownList
        TabOrder = 1
        Items.Strings = (
          'PNG'
          'JPEG')
      end
      object EdtJpegQuality: TEdit
        Left = 130
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '1'
      end
      object UdJpegQuality: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtJpegQuality
        Min = 1
        Position = 1
        TabOrder = 3
        Thousands = False
      end
      object EdtPngCompression: TEdit
        Left = 130
        Top = 107
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '0'
      end
      object UdPngCompression: TUpDown
        Left = 175
        Top = 107
        Width = 17
        Height = 23
        Associate = EdtPngCompression
        Max = 9
        TabOrder = 5
        Thousands = False
      end
      object EdtBackgroundAlpha: TEdit
        Left = 130
        Top = 136
        Width = 45
        Height = 23
        Hint = 'Background opacity for the combined image (0 = transparent, 255 = opaque).'
        NumbersOnly = True
        TabOrder = 6
        Text = '255'
      end
      object UdBackgroundAlpha: TUpDown
        Left = 175
        Top = 136
        Width = 17
        Height = 23
        Associate = EdtBackgroundAlpha
        Max = 255
        Position = 255
        TabOrder = 7
        Thousands = False
      end
      object ChkShowFileSizes: TCheckBox
        Left = 12
        Top = 169
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Show file sizes (extracts all frames when entering archive)'
        Hint = 'Reports accurate file sizes in the listing. Pre-extracts every frame on archive open, which can be slow.'
        TabOrder = 8
      end
    end
    object TshCombined: TTabSheet
      Caption = 'Combined'
      ImageIndex = 2
      DesignSize = (
        452
        400)
      object LblColumns: TLabel
        Left = 12
        Top = 24
        Width = 100
        Height = 15
        Caption = 'Columns (0=auto):'
      end
      object LblBackground: TLabel
        Left = 12
        Top = 53
        Width = 97
        Height = 15
        Caption = 'Background color:'
      end
      object LblCellGap: TLabel
        Left = 12
        Top = 82
        Width = 69
        Height = 15
        Caption = 'Cell gap (px):'
      end
      object LblBorder: TLabel
        Left = 292
        Top = 82
        Width = 73
        Height = 15
        AutoSize = False
        Caption = 'Border (px):'
      end
      object LblTCBack: TLabel
        Left = 12
        Top = 140
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Timecode background:'
      end
      object LblTCAlpha: TLabel
        Left = 292
        Top = 140
        Width = 44
        Height = 15
        Caption = 'Opacity:'
      end
      object LblTCTextColor: TLabel
        Left = 12
        Top = 169
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Timecode text color:'
      end
      object LblTCTextAlpha: TLabel
        Left = 292
        Top = 169
        Width = 44
        Height = 15
        Caption = 'Opacity:'
      end
      object LblTimestampFont: TLabel
        Left = 12
        Top = 198
        Width = 88
        Height = 15
        Caption = 'Timestamp font:'
      end
      object LblBannerBackground: TLabel
        Left = 12
        Top = 256
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Banner background:'
      end
      object LblBannerTextColor: TLabel
        Left = 12
        Top = 285
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Banner text color:'
      end
      object LblBannerFont: TLabel
        Left = 12
        Top = 314
        Width = 65
        Height = 15
        Caption = 'Banner font:'
      end
      object LblBannerPosition: TLabel
        Left = 12
        Top = 372
        Width = 86
        Height = 15
        Caption = 'Banner position:'
      end
      object EdtColumns: TEdit
        Left = 150
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '0'
      end
      object UdColumns: TUpDown
        Left = 195
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtColumns
        Max = 20
        TabOrder = 1
        Thousands = False
      end
      object PnlBackground: TPanel
        Left = 150
        Top = 49
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        Hint = 'Click to pick the contact-sheet background color.'
        ParentBackground = False
        TabOrder = 2
        OnClick = PnlBackgroundClick
      end
      object BtnBackground: TButton
        Left = 234
        Top = 49
        Width = 25
        Height = 23
        Caption = '...'
        Hint = 'Pick the contact-sheet background color.'
        TabOrder = 3
        OnClick = PnlBackgroundClick
      end
      object EdtCellGap: TEdit
        Left = 150
        Top = 78
        Width = 45
        Height = 23
        Hint = 'Pixels of empty space between adjacent frames in the grid.'
        NumbersOnly = True
        TabOrder = 4
        Text = '0'
      end
      object UdCellGap: TUpDown
        Left = 195
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtCellGap
        Max = 32767
        TabOrder = 5
        Thousands = False
      end
      object EdtBorder: TEdit
        Left = 377
        Top = 78
        Width = 45
        Height = 23
        Hint = 'Pixels of empty border around the entire contact sheet.'
        NumbersOnly = True
        TabOrder = 6
        Text = '0'
      end
      object UdBorder: TUpDown
        Left = 422
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtBorder
        Max = 32767
        TabOrder = 7
        Thousands = False
      end
      object ChkTimestamp: TCheckBox
        Left = 12
        Top = 111
        Width = 130
        Height = 17
        Caption = 'Show timestamp'
        Hint = 'Overlay each frame'#39's timecode on the contact sheet.'
        TabOrder = 8
      end
      object CbxTimestampCorner: TComboBox
        Left = 150
        Top = 107
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 9
        Items.Strings = (
          'Top left'
          'Top right'
          'Bottom left'
          'Bottom right')
      end
      object PnlTCBack: TPanel
        Left = 150
        Top = 136
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        Hint = 'Click to pick the timecode background color.'
        ParentBackground = False
        TabOrder = 10
        OnClick = PnlTCBackClick
      end
      object BtnTCBack: TButton
        Left = 234
        Top = 136
        Width = 25
        Height = 23
        Caption = '...'
        Hint = 'Pick the timecode background color.'
        TabOrder = 11
        OnClick = PnlTCBackClick
      end
      object EdtTCAlpha: TEdit
        Left = 377
        Top = 136
        Width = 45
        Height = 23
        Hint = 'Opacity of the timecode background (0 = transparent, 255 = opaque).'
        NumbersOnly = True
        TabOrder = 12
        Text = '0'
      end
      object UdTCAlpha: TUpDown
        Left = 422
        Top = 136
        Width = 17
        Height = 23
        Associate = EdtTCAlpha
        Max = 255
        TabOrder = 13
        Thousands = False
      end
      object PnlTCTextColor: TPanel
        Left = 150
        Top = 165
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        Hint = 'Click to pick the timecode text color.'
        ParentBackground = False
        TabOrder = 14
        OnClick = PnlTCTextColorClick
      end
      object BtnTCTextColor: TButton
        Left = 234
        Top = 165
        Width = 25
        Height = 23
        Caption = '...'
        Hint = 'Pick the timecode text color.'
        TabOrder = 15
        OnClick = PnlTCTextColorClick
      end
      object EdtTCTextAlpha: TEdit
        Left = 377
        Top = 165
        Width = 45
        Height = 23
        Hint = 'Opacity of the timecode text (0 = transparent, 255 = opaque).'
        NumbersOnly = True
        TabOrder = 16
        Text = '255'
      end
      object UdTCTextAlpha: TUpDown
        Left = 422
        Top = 165
        Width = 17
        Height = 23
        Associate = EdtTCTextAlpha
        Max = 255
        Position = 255
        TabOrder = 17
        Thousands = False
      end
      object EdtTimestampFont: TEdit
        Left = 149
        Top = 194
        Width = 259
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 18
      end
      object BtnTimestampFont: TButton
        Left = 414
        Top = 194
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        Hint = 'Pick the font used for the timecode overlay.'
        TabOrder = 19
        OnClick = BtnTimestampFontClick
      end
      object ChkShowBanner: TCheckBox
        Left = 12
        Top = 227
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Include file info banner'
        Hint = 'Adds a strip with the video filename and metadata to the combined image.'
        TabOrder = 20
        OnClick = ChkShowBannerClick
      end
      object PnlBannerBackground: TPanel
        Left = 150
        Top = 252
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        Hint = 'Click to pick the banner background color.'
        ParentBackground = False
        TabOrder = 21
        OnClick = PnlBannerBackgroundClick
      end
      object BtnBannerBackground: TButton
        Left = 234
        Top = 252
        Width = 25
        Height = 23
        Caption = '...'
        Hint = 'Pick the banner background color.'
        TabOrder = 22
        OnClick = PnlBannerBackgroundClick
      end
      object PnlBannerTextColor: TPanel
        Left = 150
        Top = 281
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        Hint = 'Click to pick the banner text color.'
        ParentBackground = False
        TabOrder = 23
        OnClick = PnlBannerTextColorClick
      end
      object BtnBannerTextColor: TButton
        Left = 234
        Top = 281
        Width = 25
        Height = 23
        Caption = '...'
        Hint = 'Pick the banner text color.'
        TabOrder = 24
        OnClick = PnlBannerTextColorClick
      end
      object EdtBannerFont: TEdit
        Left = 149
        Top = 310
        Width = 259
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 25
      end
      object BtnBannerFont: TButton
        Left = 414
        Top = 310
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        Hint = 'Pick the banner font.'
        TabOrder = 26
        OnClick = BtnBannerFontClick
      end
      object ChkBannerAutoSize: TCheckBox
        Left = 150
        Top = 343
        Width = 289
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Auto-size banner font to image width'
        Hint = 'Scales the banner font so it stays readable at any output width.'
        TabOrder = 28
        OnClick = ChkBannerAutoSizeClick
      end
      object CbxBannerPosition: TComboBox
        Left = 150
        Top = 368
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 27
        Items.Strings = (
          'Top'
          'Bottom')
      end
    end
    object TshPresets: TTabSheet
      Caption = 'Presets'
      ImageIndex = 4
      object LbxPresets: TListBox
        Left = 8
        Top = 8
        Width = 148
        Height = 348
        Hint = 'Defined presets. Select one to edit its properties on the right.'
        ItemHeight = 15
        TabOrder = 0
        OnClick = LbxPresetsClick
      end
      object BtnPresetAdd: TButton
        Left = 8
        Top = 362
        Width = 46
        Height = 24
        Caption = 'Add'
        Hint = 'Add a new preset with default values.'
        TabOrder = 1
        OnClick = BtnPresetAddClick
      end
      object BtnPresetRemove: TButton
        Left = 58
        Top = 362
        Width = 46
        Height = 24
        Caption = 'Del'
        Hint = 'Remove the selected preset.'
        TabOrder = 2
        OnClick = BtnPresetRemoveClick
      end
      object BtnPresetDuplicate: TButton
        Left = 108
        Top = 362
        Width = 48
        Height = 24
        Caption = 'Copy'
        Hint = 'Duplicate the selected preset under a new name.'
        TabOrder = 3
        OnClick = BtnPresetDuplicateClick
      end
      object LblPresetName: TLabel
        Left = 164
        Top = 12
        Width = 32
        Height = 15
        Caption = 'Name:'
      end
      object EdtPresetName: TEdit
        Left = 164
        Top = 28
        Width = 280
        Height = 23
        Hint = 'Unique preset name. Becomes the section heading in presets.ini.'
        TabOrder = 6
      end
      object ChkPresetEnabled: TCheckBox
        Left = 164
        Top = 58
        Width = 280
        Height = 17
        Caption = 'Enabled'
        Hint = 'Off keeps the preset in the file but hides it from the archive listing.'
        TabOrder = 7
      end
      object LblPresetDescription: TLabel
        Left = 164
        Top = 86
        Width = 67
        Height = 15
        Caption = 'Description:'
      end
      object EdtPresetDescription: TEdit
        Left = 164
        Top = 102
        Width = 280
        Height = 23
        Hint = 'Free-form note. Stored in presets.ini, not used by the plugin.'
        TabOrder = 8
      end
      object LblPresetOutputExt: TLabel
        Left = 164
        Top = 132
        Width = 80
        Height = 15
        Caption = 'Output ext:'
      end
      object EdtPresetOutputExt: TEdit
        Left = 164
        Top = 148
        Width = 80
        Height = 23
        Hint = 'Output file extension without the dot (e.g. mp4, jpg). Determines the ffmpeg container/codec unless overridden in args.'
        TabOrder = 9
      end
      object LblPresetOutputName: TLabel
        Left = 164
        Top = 178
        Width = 95
        Height = 15
        Caption = 'Output name:'
      end
      object EdtPresetOutputName: TEdit
        Left = 164
        Top = 194
        Width = 280
        Height = 23
        Hint = 'Output filename template. Variables: %basename%, %name%, %ext%. Use / for subfolders inside the archive.'
        TabOrder = 10
      end
      object LblPresetArgs: TLabel
        Left = 164
        Top = 224
        Width = 80
        Height = 15
        Caption = 'ffmpeg args:'
      end
      object MemoPresetArgs: TMemo
        Left = 164
        Top = 240
        Width = 280
        Height = 100
        Hint = 'ffmpeg arguments inserted after the input. Forbidden: -i, -y, -n, pipe:0/1/2. The same template variables as Output name expand here too.'
        ScrollBars = ssVertical
        TabOrder = 11
      end
    end
    object TshLimits: TTabSheet
      Caption = 'Size limit'
      ImageIndex = 3
      DesignSize = (
        452
        400)
      object LblLimitsHint: TLabel
        Left = 12
        Top = 24
        Width = 424
        Height = 15
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
        Caption = 'Maximum longer side in pixels (0 = no limit)'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object LblFrameMax: TLabel
        Left = 12
        Top = 53
        Width = 148
        Height = 15
        Caption = 'Separate frames longer side:'
      end
      object LblCombinedMax: TLabel
        Left = 12
        Top = 82
        Width = 156
        Height = 15
        Caption = 'Combined image longer side:'
      end
      object EdtFrameMax: TEdit
        Left = 170
        Top = 49
        Width = 60
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '0'
      end
      object UdFrameMax: TUpDown
        Left = 230
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtFrameMax
        Max = 7680
        Increment = 16
        TabOrder = 1
        Thousands = False
      end
      object EdtCombinedMax: TEdit
        Left = 170
        Top = 78
        Width = 60
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '0'
      end
      object UdCombinedMax: TUpDown
        Left = 230
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtCombinedMax
        Max = 7680
        Increment = 16
        TabOrder = 3
        Thousands = False
      end
    end
  end
  object PnlButtons: TPanel
    Left = 0
    Top = 430
    Width = 460
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    DesignSize = (
      460
      40)
    object BtnDefaults: TButton
      Left = 8
      Top = 6
      Width = 100
      Height = 28
      Anchors = [akLeft, akBottom]
      Caption = 'Reset Defaults'
      TabOrder = 0
      OnClick = BtnDefaultsClick
    end
    object BtnApply: TButton
      Left = 215
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akRight, akBottom]
      Caption = 'Apply'
      TabOrder = 1
      OnClick = BtnApplyClick
    end
    object BtnOK: TButton
      Left = 296
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akRight, akBottom]
      Caption = 'OK'
      Default = True
      TabOrder = 2
      OnClick = BtnOKClick
    end
    object BtnCancel: TButton
      Left = 377
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akRight, akBottom]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 3
    end
  end
  object ColorDlg: TColorDialog
    Options = [cdFullOpen]
    Left = 408
    Top = 8
  end
  object FontDlg: TFontDialog
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    Options = [fdEffects, fdForceFontExist]
    Left = 344
    Top = 8
  end
end
