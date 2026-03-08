clear
clc
runOnLocal = 0; % 1 or 0

%% Find tests Folder and test .mat file
[mFolder, mName ] = fileparts(mfilename('fullpath'));
functionName = mName(find(mName=='_',1)+1:end); %functionName ='ReadRecord';

testsFoldersList = jsondecode(fileread(fullfile(mFolder,'testsFolder.json'))); 
if runOnLocal
    testsFolder = testsFoldersList.local;   %#ok<UNRCH>
else
    testsFolder = testsFoldersList.global;  %#ok<UNRCH>
end

testsFolderFunc = fullfile(testsFolder,'ReadRecord'); % testing folder of the specific function 
if exist(testsFolderFunc,'file')~=7
    error(['Testing Folder "' testsFolderFunc '" does not exist!'])
end
casesStruct = load( fullfile( testsFolderFunc ,['testScenatios_' functionName '.mat']) );

%% Run Over all Cases
passArr=nan(size(casesStruct.cases));
for test_i = 1:numel(casesStruct.cases)
    %%
    testCase = casesStruct.cases(test_i);
    disp([10 'Test Case Num ' num2str(test_i) ':'])
    disp(testCase.input);
    
    try
        [currOutput.nOfFrames , currOutput.imSize ] = GetNumOfFrames(fullfile(testsFolderFunc, testCase.input.recName));
        if ~isequaln(currOutput,testCase.output)
            passArr(test_i) = false;
            disp(' < FAILED >')
            [same, diff_recOutput, diff_groundTruth] = comp_struct(currOutput,testCase.output);
            disp('Fields that are different: ')
            disp('  Expected : '); disp(diff_groundTruth)
            disp('  Recieved : '); disp(diff_recOutput)
            warning(['Case ' num2str(test_i) ': wrong output! ']);
        else
            passArr(test_i) = true;
            disp(' < PASSED >')
        end
    catch err
        if isfield(testCase.output,'error')
            % update error string, in case testsFolderFunc was changed
            recievedError  = strrep(err.message                    , testsFolderFunc             ,'<TestsFolder>');
            expectedEror = strrep(testCase.output.error.message  , casesStruct.testsFolderFunc ,'<TestsFolder>');
            
            % compare errors
            if isequaln(recievedError,expectedEror) 
                passArr(test_i) = true;
                disp('< PASSED >')
            else
                passArr(test_i) = false;
                disp(' < FAILED >')
                warning(['Case ' num2str(test_i) ': failed as expected but the error is wrong ! '])
                disp(['Expected Error : ' expectedEror  ]);
                %disp(testCase.output.error.stack)
                disp(['Recieved Error : ' recievedError   ])
                %disp(err.stack)
            end
        else
            passArr(test_i) = false;
            disp(' < FAILED >')
            passArr(test_i) = false;
            warning(['Case ' num2str(test_i) ':  FAILED on running ! Error = "' err.message '"']);
            
        end
    end
    %%
end

disp([10 '~~~~~~~~~~~~~~~~~~~~~~ Summary ~~~~~~~~~~~~~~~~~~~~~~~~~' ])
if all(passArr)
    disp([ functionName ' : Congradulations - All tests have passed !' ])
else
    disp([ functionName '() Test ' 10 ' Passed : ' num2str(find(passArr==1)) 10 ' Failed : ' num2str(find(passArr==0)) 10 ' Ignored : ' num2str(find(isnan(passArr)))  ])
end