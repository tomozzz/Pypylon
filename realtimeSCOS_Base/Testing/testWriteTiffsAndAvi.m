% rec  = ReadRecord('C:\Users\Vika\OneDrive - Bar-Ilan University - Students\PhD Research\SCOS\Records\Intralipid\400um fiber\Intralipid 0.49%\Objective20x_dist0_noLens\Tint22ms_Gain20_FR45.3Hz_background');
rec1 = rand(10,10,10)*255;
folder = '.\TestRec\Matlab\Synthetic';
if ~exist(folder,'file'); mkdir(folder);  end

rec2 = rec1 + 1000;
%% write
WriteTiffSeq(     [ folder '\rec1_mono8_tiffs' ], rec1 ,"Mono8"     );
WriteTiffSeq(     [ folder '\rec1_mono12_tiffs'], rec1,"Mono12"    );
WriteTiffSeq(     [ folder '\rec2_mono12_tiffs'], rec2,"Mono12"    );

WriteAvi([ folder '\rec1_mono8.avi'   ], rec1 ,"Mono8" ,100);
% WriteAvi([ folder '\rec1_uint16.avi'  ], rec1 ,"Mono12",100); % Not Working

%% read 
rec1_tiff_mono8  = ReadRecord([ folder '\rec1_mono8_tiffs'   ]);
rec1_tiff_mono12 = ReadRecord([ folder '\rec1_mono12_tiffs'  ]);
rec2_tiff_mono12 = ReadRecord([ folder '\rec2_mono12_tiffs'  ]);
rec1_avi_mono8   = ReadRecord([ folder '\rec1_mono8.avi'     ]);
% rec1_avi_uint16  = ReadRecord([ folder '\rec1_mono12.avi'    ]);
[rec1_avi_3to6, v] = Avi2Matrix([ folder '\rec1_mono8.avi'     ], 4, 3);
rec1_tiff_mono12_3to6 = ReadRecord([ folder '\rec1_mono12_tiffs'  ],  4, 3);
rec1_tiff_mono8_3to6 = ReadRecord([ folder '\rec1_mono8_tiffs'  ],  4, 3);

%% Assert
assert( isequal( uint8(rec1)  , rec1_tiff_mono8  ), 'Rec1 Tiff Mono8  - Fail');
assert( isequal( uint16(rec1) , rec1_tiff_mono12 ), 'Rec1 Tiff Mono12 - Fail');
assert( isequal( uint16(rec2) , rec2_tiff_mono12 ), 'Rec2 Tiff Mono12 - Fail');
assert( isequal( uint8(rec1)  , rec1_avi_mono8   ), 'Rec1 Avi Mono8   - Fail');
assert( isequal( uint8(rec1(:,:,3:6))  , rec1_avi_3to6)         , 'Rec1 Avi Mono8  Frames 3 to 6 - Fail');
assert( isequal( uint16(rec1(:,:,3:6)) , rec1_tiff_mono12_3to6) , 'Rec1 tiffs Mono12  Frames 3 to 6 - Fail');
assert( isequal( uint8(rec1(:,:,3:6))  , rec1_tiff_mono8_3to6)  , 'Rec1 tiffs Mono8  Frames 3 to 6 - Fail');
 
%% Connect Camera! 
nOfFrames = 10;
camParams  = struct(); % removed any previous fields
camParams.ExposureTime = 10000;
camParams.addToFilename = 1;
camParams.AcquisitionFrameRate = 120;
setupParams = struct(); % removed any previous fields
setupParams.Cover = 'On';
folderRec = '.\TestRec\Matlab\FromCamera';
saveFormat = '.avi';
prefix = 'rec4';
suffix = 'x';
forceWrite =1;
plotFlag =1;
[ rec4, filename4, info4 ] = RecordFromCamera(nOfFrames,camParams,setupParams,folderRec,saveFormat,prefix,suffix,forceWrite,plotFlag);
info4.cam
info4.name
info4.setup
%%
setupParams.Cover = 'On';
setupParams.Scene = '';
setupParams.addToFilename = 1;
prefix = 'rec6';
saveFormat = '.tiff';
[ rec5, filename5, info5 ] = RecordFromCamera(nOfFrames,camParams,setupParams,folderRec,saveFormat,prefix,suffix,forceWrite,plotFlag);
