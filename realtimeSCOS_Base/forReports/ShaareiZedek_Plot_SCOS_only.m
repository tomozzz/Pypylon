%% Load Data
clear
participantID = 'A13';
plotIflag = 1;

% recordsFolder = 'D:\Vika\OneDrive - Bar Ilan University\SCOS_Records\ShaareiZedek';
recordsFolder = 'E:\ShaareiZedek\SCOS_Records';
figuresFolder = fullfile(recordsFolder,'Docs','figs');

SCOSrecordsDir = dir([ recordsFolder '\' participantID ' *']);
SCOSrecordsDir2 = dir([recordsFolder '\' SCOSrecordsDir.name '\Main*']);
if numel(SCOSrecordsDir2) ~=1
    error('could not find SCOS name');
end
SCOSrecordsDir3 = dir([recordsFolder '\' SCOSrecordsDir.name '\' SCOSrecordsDir2.name '\LocalStd*.mat']);
if numel(SCOSrecordsDir3) ~=1
    disp('More than one file found:')
    disp({SCOSrecordsDir3.name}')
    fileNum = input('which one to choose? ');
else
    fileNum = 1;
end
SCOSfile = fullfile([recordsFolder '\' SCOSrecordsDir.name '\' SCOSrecordsDir2.name '\' SCOSrecordsDir3(fileNum).name]);

rawName = SCOSrecordsDir2.name;
scosFolderName = SCOSrecordsDir.name;
titleStr = [ scosFolderName ]; % ' ' strrep(rawName,'_',' ') ];
frameRate = ExtractParametersFromString(rawName,'FR'); 
   
%% Timing
timingDir = dir([ recordsFolder '\' scosFolderName '\*timing*.txt']);
if ~isempty(timingDir)
    timingFile = fullfile(recordsFolder , scosFolderName ,timingDir(1).name);
    Timing = readtable(timingFile);
    baselineTime = Timing.Time{1};
    if nnz(baselineTime==':') == 1
       baselineTime = [ baselineTime , ':00'] ;
    end

    if exist(timingFile,'file')
        if exist([fileparts(SCOSfile) '\StartTime.mat'],'file')
            st = load([fileparts(SCOSfile) '\StartTime.mat']);
            startTimeScos = timeofday(st.startTime);
            clear st
        else
            startTimeScos = getSCOSstartTime(fileparts(SCOSfile));
        end
    end
    baselineToScosStart = minutes(duration(startTimeScos) - duration(baselineTime));
    endTime = minutes(duration(Timing.Time{end},'InputFormat','hh:mm') - duration(baselineTime));
else
    error(['Could not Find Timing File for ' participantID ]);
    baselineToScosStart = 0;
end

%% Calc rBFi
S = load(SCOSfile);
BFi = 1./S.corrSpeckleContrast{1};
scosTimeVec = S.timeVec / 60 + baselineToScosStart; % convert to min
xLabelStr = 'time [min]';
rBFi = BFi/mean(BFi(1:round(10*frameRate))); % normalize by first 10 seconds
        
%% Plot
fig8 = figure('Name',['rBFi: '  rawName ],'Units','Normalized','Position',[0.1,0.3,0.72 ,0.4]);
if plotIflag; N = 2; else; N=1; end
subplot(N,1,1);
plot(scosTimeVec,rBFi);
ylim([0 min(10,max(rBFi))])
xlabel(xLabelStr)
ylabel('rBFi');
xlim([-0.2 endTime+4]);
grid on
set(gca,'FontSize',10);
markTiming(timingFile);
title(titleStr,'interpreter','none','FontSize',14)

if plotIflag
    subplot(N,1,2)
    plot(scosTimeVec,S.meanVec{1});
    xlabel(xLabelStr)
    ylabel('<I> [DU]');
    set(gca,'FontSize',10);
    xlim([-0.2 endTime+4]);
    grid on
end

%% Save
if plotIflag; addStr='_with_I'; else; addStr='_no_I'; end
savefig(fig8,[figuresFolder '\' participantID '_scosOnly' addStr '.fig']);
save([fileparts(figuresFolder) '\short_data\'  participantID '_scos_only.mat'],'rBFi','scosTimeVec','BFi');