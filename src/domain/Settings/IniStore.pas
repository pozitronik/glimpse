{Abstract key-value INI store. The domain settings code (TPluginSettings,
 the settings groups, THotkeyBindings) depends on this interface;
 TUnicodeIniFile implements it, so the persistence backend can be
 substituted — notably for tests with no file on disk.}
unit IniStore;

interface

type
  IIniFile = interface
    ['{2C9E5A14-7B3D-4F86-A1C0-9D4E8B6F0357}']
    function ReadString(const Section, Ident, Default: string): string;
    procedure WriteString(const Section, Ident, Value: string);
    function ReadInteger(const Section, Ident: string; Default: Longint): Longint;
    procedure WriteInteger(const Section, Ident: string; Value: Longint);
    function ReadBool(const Section, Ident: string; Default: Boolean): Boolean;
    procedure WriteBool(const Section, Ident: string; Value: Boolean);
    function ValueExists(const Section, Ident: string): Boolean;
    {Commits buffered writes to the backing store.}
    procedure UpdateFile;
  end;

implementation

end.
