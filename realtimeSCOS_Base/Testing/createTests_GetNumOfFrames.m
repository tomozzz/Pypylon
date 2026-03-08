clear 

%% find testsFolder of current 
testsFoldersList = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')),'testsFolder.json')));
testsFolderFunc  = [ testsFoldersList.local filesep 'ReadRecord' ]; % create tests always in the local tets folder


%% Create test Cases
cases(1).input.recName = 'AviSingleFile_Tint3ms_Gain0_FR100Hz';    
cases(2).input.recName = 'Tiffs_f25mm_Tint0.1ms_Gain20_FrameRate20Hz';
cases(3).input.recName = 'Tiffs_f25mm_Tint0.1ms_Gain20_FrameRate20Hz\Basler_acA1440-220um__40335410__20230626_141819502_0005.tiff';
cases(4).input.recName = 'SeveralAviFiles\file1.avi';              
cases(5).input.recName = 'SeveralAviFiles';     % suppose to fail 
cases(6).input.recName = 'EmptyFolder';         % suppose to fail
cases(7).input.recName = 'notExistingRec';      % suppose to fail

%% Run test Cases

% success cases
for n=1:4
    fprintf('Case %d: recName="%s"\t; ',n,cases(n).input.recName)
    [ cases(n).output.nOfFrames , cases(n).output.imSize] = GetNumOfFrames(fullfile(testsFolderFunc,cases(n).input.recName));
    fprintf('nOfFrames=%g ; imsize=[%g %g]\n', cases(n).output.nOfFrames , cases(n).output.imSize(1), cases(n).output.imSize(2));
end

% cases with error
for n=5:7
    try
        fprintf('Case %d: recName="%s"\t; ',n,cases(n).input.recName)
        [ cases(n).output.nOfFrames , cases(n).output.imSize] = GetNumOfFrames(fullfile(testsFolderFunc,cases(n).input.recName));
        fprintf(' Wrong!! Should no get here!\n');
    catch err
        cases(n).output.error = err;
        fprintf('err = "%s" \n',err.message);
    end
end


%% Save .mat file with all scenarios
[mFolder, mName ] = fileparts(mfilename('fullpath'));
functionName = mName(find(mName=='_',1)+1:end); %functionName ='ReadRecord';

save(fullfile(testsFolderFunc,['testScenatios_' functionName '.mat']),'cases','testsFolderFunc');

