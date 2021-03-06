Unit TERRA_Package;
{$I terra.inc}

{-$DEFINE ALLOWEXTERNAL}

Interface
Uses TERRA_Object, TERRA_String, TERRA_Utils, TERRA_FileUtils, TERRA_Stream, TERRA_Collections, TERRA_List;

Const
  terraHeader:FileHeader = 'TePK';

  resCompressed = 1;
  resEncrypted  = 2;

Type
  TERRAPackage = Class;

  ResourceInfo = Class(TERRAObject)
    Protected
      _Owner:TERRAPackage;
      _FileName:TERRAString;                // Resource name

      _Offset:Cardinal;            // Offset of the resource
      _Size:Cardinal;              // Size of the resource (bytes)
      _CRC:Cardinal;

      _ExternalPath:TERRAString;        // External path/override

    Public
      Constructor Create(Owner:TERRAPackage; Source:TERRAStream);

      Function GetLocation:TERRAString;

      Property FileName:TERRAString Read _FileName;
      Property Size:Cardinal Read _Size;
      Property Offset:Cardinal Read _Offset Write _Offset;
      Property CRC:Cardinal Read _CRC;
  End;

  TERRAPackage = Class(TERRAObject)
    Protected
      _Name:TERRAString;
      _Location:TERRAString;
      _TableOffset:Cardinal; // Table position in the file
      _CRC:Cardinal;

      _Resources:TERRAList; // List of all resources within the file

      Function GetCRC():Cardinal;

    Public
      Path:TERRAString;  // File override path

      // Load a package from disk
      Constructor Create(FileName:TERRAString);

      Procedure Release; Override;


      // Read package contents
      Function Load():Boolean;

      // unloads resources
      Function Unload():Boolean;

      // Searches for a resource inside a package
      Function FindResourceByName(Const ResourceName:TERRAString):ResourceInfo;

      Function FindResourceByIndex(Index:Integer):ResourceInfo;

      // Loads a resource into a stream
      // Note: If resource file is found in search path the is loaded from there
      // This can be used for patches/mods
      Function LoadResource(Resource:ResourceInfo):TERRAStream;

      // Package name
      Property Name:TERRAString Read _Name;
      Property Resources:TERRAList Read _Resources;
    End;

Implementation
Uses TERRA_Error, TERRA_CRC32, TERRA_Application, TERRA_OS, TERRA_Log, TERRA_ResourceManager,
  TERRA_Engine, TERRA_FileStream, TERRA_FileManager, TERRA_MemoryStream;

Constructor ResourceInfo.Create(Owner:TERRAPackage; Source:TERRAStream);
Begin
  _Owner := Owner;

  Source.ReadString(_FileName); //Read resource name
  Source.ReadCardinal(_Offset);       // Read offset of the resource
  Source.ReadCardinal(_Size);           // Size of the resource
  Source.ReadCardinal(_CRC);         // Read CRC
End;

Function ResourceInfo.GetLocation:TERRAString;
Begin
   Result := _Owner._Location + PathSeparator + _Filename;
End;


{ TERRAPackage }
Constructor TERRAPackage.Create(FileName:TERRAString);
Begin
  _Location := FileName;
  _Name := GetFileName(FileName, True);
  _Resources := Nil;
End;

Procedure TERRAPackage.Release;
Begin
  Unload();
End;

Function TERRAPackage.FindResourceByIndex(Index:Integer):ResourceInfo;
Begin
  Result := ResourceInfo(_Resources.GetItemByIndex(Index));
End;

Function TERRAPackage.Unload:Boolean;
Begin
  ReleaseObject(_Resources);
  Result := True;
End;

Function TERRAPackage.Load():Boolean;
Var
  I,J:Integer;
  ResCount:Integer;
  S:TERRAString;
  Header:FileHeader;
  Resource:ResourceInfo;
  Source:TERRAStream;
Begin
  Self.Unload();

  Result := False;

  Source := FileStream.Open(_Location, smRead);

  Source.ReadHeader(Header);
  If Header<>TERRAHeader Then
  Begin
    Engine.RaiseError('Invalid header. ['+Source.Name+']');
    ReleaseObject(Source);
    Exit;
  End;

  Source.ReadInteger(ResCount); //Read filetable info
  Source.ReadCardinal(_TableOffset);
  Source.Seek(_TableOffset);

  _Resources := TERRAList.Create(collection_Unsorted);
  For I:=1 To ResCount Do
  Begin
    Resource := ResourceInfo.Create(Self, Source);
    _Resources.Add(Resource);

    {$IFDEF ALLOWEXTERNAL}
    Resource._ExternalPath := FileManager.Instance.SearchResourceFile(GetFileName(Resource._FileName, False));
    {$ELSE}
    Resource._ExternalPath := '';
    {$ENDIF}
  End;

  ReleaseObject(Source);
  Result := True;
End;

//Searches for a resource within the file table
//If not found returns nil
Function TERRAPackage.FindResourceByName(Const ResourceName:TERRAString):ResourceInfo;
Var
  It:TERRAIterator;
  Res:ResourceInfo;
Begin
  Result := Nil;
  If _Resources = Nil Then
    Exit;

  It := _Resources.GetIterator();
  While It.HasNext() Do
  Begin
    Res := ResourceInfo(It.Value);
    If (StringEquals(Res._FileName, ResourceName)) Then
    Begin
      Result := Res;
      Break;
    End;
  End;
  ReleaseObject(It);

(*  If Not Assigned(Result)Then
    Log(logWarning, 'Package', 'Resource not found.['+ResourceName+']');*)
End;

//Loads a resource from the package into a stream
Function TERRAPackage.LoadResource(Resource:ResourceInfo):TERRAStream;
Var
  Source:TERRAStream;
Begin
     Result := Nil;

  If Not Assigned(Resource) Then
  Begin
    Engine.RaiseError('Package.LoadResource(): Null resource');
    Exit;
  End;

//  Log(logDebug,'Package', 'Loading resource '+Resource._Name);

  If (Resource._ExternalPath<>'') Then
  Begin
    Result := MemoryStream.Create(Resource._ExternalPath);
    Result.Name := Resource._ExternalPath;
    Exit;
  End;

  Result := MemoryStream.Create(Resource._Size);
  Result.Name := Resource.GetLocation();

  Source := FileStream.Open(_Location, smRead);
  Source.Copy(Result, Resource._Offset, Resource._Size);
  Result.Seek(0);
  ReleaseObject(Source);
End;

Function TERRAPackage.GetCRC:Cardinal;
Var
  Source:TERRAStream;
Begin
  If _CRC=0 Then
  Begin
    Source := Engine.Files.OpenFile(_Location);
    _CRC := GetCRC32(Source);
    ReleaseObject(Source);
  End;
  Result:=_CRC;
End;

End.
