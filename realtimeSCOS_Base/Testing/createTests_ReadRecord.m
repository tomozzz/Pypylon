clear 

% find testsFolderFunc
testsFolderFuncsList = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')),'testsFolder.json')));
testsFolderFunc  = [ testsFolderFuncsList.local filesep 'ReadRecord' ]; % create tests always input the local tets folder

% Create ReadRecord test Cases
recName1 = 'AviSingleFile_Tint3ms_Gain0_FR100Hz';
recName2 = 'Tiffs_f25mm_Tint0.1ms_Gain20_FrameRate20Hz';
recName3 = 'SeveralAviFiles\file1.avi';
recName4 = 'SeveralAviFiles';   % suppose to fail
recName5 = 'EmptyFolder';       % suppose to fail
recName6 = 'notExisting';       % suppose to fail

n = 1;

% 1A. Avi File, all params
cases(n).input.recName = recName1;
cases(n).input.nOfFrames = 2;
cases(n).input.startFrame = 7;

fprintf('Case %d: %s \n', n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input, testsFolderFunc);

%  1B. Avi File, Inf num of frames
n = n + 1 ;
cases(n).input.recName = recName1;
cases(n).input.nOfFrames = Inf;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input, testsFolderFunc);

%  1C. Avi File, Inf num of frames, with start frame
n= n + 1;
cases(n).input.recName = recName1;
cases(n).input.nOfFrames = Inf;
cases(n).input.startFrame = 7;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input, testsFolderFunc);

% 1D. Avi File, 3 num of frames
n= n + 1;
cases(n).input.recName = recName1;
cases(n).input.nOfFrames = 3;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input, testsFolderFunc);


% 1E. Avi File, no params
n= n + 1;
cases(n).input.recName = recName1;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);

%% Tiff
% 2A. Tiff Files, all Params
n = n + 1 ;
cases(n).input.recName = recName2;
cases(n).input.nOfFrames = 3;
cases(n).input.startFrame = 2;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);

% 2B. Tiff Files, all Params - expected error - too much frames requested
n = n + 1 ;
cases(n).input.recName = recName2;
cases(n).input.nOfFrames = 20; % more than exist input folder
cases(n).input.startFrame = 2;

fprintf('Case %d (Error): %s\n', n, cases(n).input.recName);
try
    cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);
catch err
    cases(n).output.error = err;
end

% 2C. Tiff Files, Inf frames
n = n + 1 ;
cases(n).input.recName = recName2;
cases(n).input.nOfFrames = Inf;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);

% 2C. Tiff Files, no nOfframes (supposed to reaad all)
n = n + 1 ;
cases(n).input.recName = recName2;
cases(n).input.startFrame = 2;

fprintf('Case %d: %s\n', n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);

% 3A. Single .Avi File
n = n + 1 ;
cases(n).input.recName = recName3;
cases(n).input.nOfFrames = 5;
cases(n).input.startFrame = 20;

fprintf('Case %d: Input : %s ; nOfFrames=%d ; startFrame=%d\n ',n, cases(n).input.recName,cases(n).input.nOfFrames,cases(n).input.startFrame);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);
fprintf(['Output : Size = [' num2str(size(cases(n).output.rec)) ']\n']);
disp(cases(n).output.info.name)


% 3B. Single .Avi File Inf Frames
n = n + 1 ;
cases(n).input.recName = recName3;
cases(n).input.nOfFrames = Inf;
cases(n).input.startFrame = 2;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);

% 3C. Single .Avi File no Frames
n = n + 1 ;
cases(n).input.recName = recName3;

fprintf('Case %d: %s\n',n, cases(n).input.recName);
cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);
n = n + 1 ;

% 4a. Several .avi files input folder
n = n + 1 ;
cases(n).input.recName = recName4;
cases(n).input.nOfFrames = Inf;

fprintf('Case %d (Error): %s\n', n, cases(n).input.recName);
try
    cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);
catch err
    cases(n).output.error = err;
end

% 4b. Empty Folder
n = n + 1 ;
cases(n).input.recName = recName5;
cases(n).input.nOfFrames = Inf;

fprintf('Case %d (Error): %s\n', n, cases(n).input.recName);
try
    cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);
catch err
    cases(n).output.error = err;
end

% 4c. Not Existing
n = n + 1 ;
cases(n).input.recName = recName6;

fprintf('Case %d (Error): %s\n', n, cases(n).input.recName);
try
    cases(n).output = run_ReadRecord(cases(n).input,testsFolderFunc);
catch err
    cases(n).output.error = err;
end

%% Save .mat file with all scenarios
save(fullfile(testsFolderFunc,'testScenatios_ReadRecord.mat'),'cases','testsFolderFunc');

