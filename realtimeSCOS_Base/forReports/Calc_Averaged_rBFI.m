function [fig1,fig2,avgBFI,timeVec_cut, avgOverEpoch , stdOverEpoch]  = Calc_Averaged_rBFI(recName,avgWindowSeconds,titleAddText,useCorrected,plotStd,choose_epoches)

%% User Input
if ~exist('recName','var')    
    try load('lastFolder.mat'); catch ; end
    if ~exist('lastFolder','var'); lastFolder = '..\Records\Japan\OneChannel\1000micronFiber'; end
    recName = uigetdir(lastFolder);
    if recName == 0; return; end
    lastFolder = fileparts(recName);
    save('lastFolder.mat','lastFolder');
end

if exist(recName,'file') ~= 7
   error([recName ' record does not exist!']); 
end
if ~exist('titleAddText','var')
    titleAddText = ''; %'right position 9&10';
end

if ~exist('avgWindowSeconds','var') 
    if nargin < 1 % GUI mode
        answer = inputdlg('Window length- for averaging [sec]','',[1 25],{'10'});
        avgWindowSeconds = str2double(answer);
        if isnan(avgWindowSeconds)
            error(['Illeagal answer for averaging window "' answer '"']);
        end
    else    
        avgWindowSeconds = 5;
    end
end

if ~exist('useCorrected','var')
    useCorrected = 1;
end
    
plotOnlyBFI = 0;
if ~exist('plotStd','var') || isempty(plotStd)
    plotStd = 1;
end
if ~exist('choose_epoches','var') || isempty(choose_epoches)
    choose_epoches = []; %[3,4,5];
end
%%
titlePrefix = '';
if useCorrected
    savePrefix = ['NoiseSubtracted']; 
    titlePrefix = [ titlePrefix 'Noise Subtracted' ];
else
    savePrefix = ['NoNoiseSubtraction'];
    titlePrefix = [ titlePrefix 'Not Noise Subtracted' ];
end

%% Parse user input
if contains(recName,'Hand','IgnoreCase',true)
    taskName = 'FingerGrip'; 
    titleTaskName = 'Fingers Grip Task'; 
    taskStart = 1*60; % 1min
    taskDuration   = 2*60; % 
    taskColor = [1 0.65 0];
elseif contains(recName,'Verbal','IgnoreCase',true)
    taskName = 'Verbal'; 
    titleTaskName = 'Verbal Task';
%     taskDuration   = 40;
%     taskStart = 50 + 90*[0:3]; 

    taskDuration   = 30; %  0.5 minute
    taskStart = 30 + 60*[0:4]; % each minut
    taskColor = [0 0 1];
elseif contains(recName,'nBack','IgnoreCase',true)
    taskName = 'nBack'; % 'FingerGrip' 'Verbal'
    titleTaskName = 'n-Back Task'; 
%     taskDuration   = 40; %  0.5 minute
%     taskStart = 50 + 90*[0:3]; % each minut
    taskDuration   = 30; %  0.5 minute
    taskStart = 17 + 60*[0:4] ; % each minut
    taskColor = [0 1 0];
else
    error('Unknow task');
end

if isempty(choose_epoches)
    choose_epoches = 1:numel(taskStart);
else
    titlePrefix = [ titlePrefix '; Epoches ' num2str(choose_epoches) ] ;
end
    
% find participant name from record name
idx1 = strfind(recName,'Head');
if isempty(idx1)
    idx1 = strfind(recName,'Hand');
end
if isempty(idx1)
    participantName = '';
else
    participantName = recName(find(recName(1:idx1)==filesep,1,'last')+1:idx1-1);
    if participantName(end)=='_';
        participantName(end) = [];
    end
end

secForNorm = 5; 
titleStart = [ participantName ' ' titleAddText ' ' titleTaskName ];
upFolders = strsplit(recName,filesep);
% rawName = strrep( strjoin(upFolders(end-2:end),'; '), '_',' ');
shortRecName = strjoin(upFolders(end-2:end));

%% Load the data
% if useCorrected
    matName = dir([recName '\LocalStd9x9_corr.mat']);
% else
%     matName = dir([recName '\LocalStd9x9.mat']);
% end

D = load([ recName filesep matName(1).name]);

%% Calc Averaged Signals
if iscell(D.rawSpeckleContrast)
   nOfChannels = numel(D.rawSpeckleContrast);
else
   nOfChannels = 1;
end
dt = diff(D.timeVec(1:2)); 
avgWindowSamples = round(avgWindowSeconds/dt);
if avgWindowSeconds==0
    meanFilter = 1;
    avgWindowSamples = 1;
else
    meanFilter = ones(avgWindowSamples,1)./avgWindowSamples;
end

% division into epoches :
secBeforeEpoch = 10;
secAfterEpoch = 20;
secForRef = 5;
epochTime = -secBeforeEpoch:dt:taskDuration+secAfterEpoch-dt;
indForRef = 1:round(secForRef/dt);
epoch = cell(1,nOfChannels);
avgOverEpoch = cell(1,nOfChannels);

for channel_i = 1:nOfChannels
    if ~useCorrected
        if isfield(D,'rawSpeckleContrast_jumpsCorrected') && numel(D.rawSpeckleContrast_jumpsCorrected)>=channel_i && ~isempty(D.rawSpeckleContrast_jumpsCorrected{channel_i})
            contrastVec=D.rawSpeckleContrast_jumpsCorrected{channel_i};
        else
            contrastVec=D.rawSpeckleContrast{channel_i};
        end%-----
    else
        if isfield(D,'rawSpeckleContrast_jumpsCorrected') && numel(D.rawSpeckleContrast_jumpsCorrected)>=channel_i && ~isempty(D.rawSpeckleContrast_jumpsCorrected{channel_i})
            contrastVec = D.corrSpeckleContrast_jumpsCorrected{channel_i};
        else
            contrastVec = D.corrSpeckleContrast{channel_i};
        end
    end
    if ~isfield(D,'meanVec') 
        if isfield(D,'imMeanVec')
            D.meanVec = D.imMeanVec;
        else
            error('no meanVec or imMeanVec field in data file')
        end
    end
    avgI{channel_i}   = filter(meanFilter,1,D.meanVec{channel_i});
    avgI{channel_i}   = avgI{channel_i}(avgWindowSamples:end); %#ok<*AGROW>
    %         avgK2{channel_i}  = filter(meanFilter,1,contrastVec);
    %         avgK2{channel_i}  = avgK2{channel_i}(avgWindowSamples:end);
    avgBFI{channel_i} = filter(meanFilter,1,1./contrastVec);
    avgBFI{channel_i} = avgBFI{channel_i}(avgWindowSamples:end);

    timeVec_cut = D.timeVec(avgWindowSamples:end);
    
    if numel(taskStart) > 1
        epoch{channel_i}.rI    = nan(numel(taskStart),numel(epochTime));
        epoch{channel_i}.rBFI = nan(numel(taskStart),numel(epochTime));
        % loop over epoches
        for epoch_i=1:numel(taskStart) 
            if ~ismember(epoch_i,choose_epoches); continue; end
            indStart = find(timeVec_cut >= taskStart(epoch_i)-secBeforeEpoch,1);
            indEnd   = indStart + numel(epochTime) - 1; %find(timeVec_cut >= taskStart(k)+taskDuration+secAfterEpoch,1);
            if indEnd > numel(avgI{channel_i})
                % pad the data 
                avgI{channel_i}(end+1:indEnd) = nan;
                avgBFI{channel_i}(end+1:indEnd) = nan;
                timeVec_cut(end+1:indEnd) = nan;
            end
            epoch{channel_i}.rI(epoch_i,:)   =  avgI{channel_i}(indStart:indEnd)./mean(avgI{channel_i}(indStart+indForRef));
            epoch{channel_i}.rBFI(epoch_i,:) =  avgBFI{channel_i}(indStart:indEnd)./mean(avgBFI{channel_i}(indStart+indForRef));
        end
        avgOverEpoch{channel_i}.rI = mean(epoch{channel_i}.rI,1,'omitnan');
        avgOverEpoch{channel_i}.rBFI = mean(epoch{channel_i}.rBFI,1,'omitnan');
        stdOverEpoch{channel_i}.rI = std(epoch{channel_i}.rI,0,1,'omitnan');
        stdOverEpoch{channel_i}.rBFI = std(epoch{channel_i}.rBFI,0,1,'omitnan');
        avgOverEpoch{channel_i}.time = epochTime;
        avgOverEpoch{channel_i}.time = epochTime;
    end
end

%%  Plot over all time
fig1 = figure('Name',[ shortRecName  ' ' titlePrefix ' All record Average ' num2str(avgWindowSeconds) ' Seconds' ],'Units','Normalized','Position',[0 0.8-nOfChannels*0.17 0.8 0.1+nOfChannels*0.17]);
if plotOnlyBFI; Nx=1; else; Nx = 2; end
Ny=nOfChannels;
for channel_i = 1:nOfChannels
    if ~plotOnlyBFI
        % Plot relative Intensity
        subplot(Ny,Nx,(channel_i-1)*Nx+1);
        plot(timeVec_cut, avgI{channel_i}./median(avgI{channel_i}(1:round(secForNorm/dt))) );
        xlabel('time [sec]');
        ylabel('rI ');
        if channel_i == 1
            if nOfChannels==1
                title({titleStart ,['relative Intensity average over ' num2str(avgWindowSeconds) ' sec'] });            
            else
                title({titleStart ,['relative Intensity average over ' num2str(avgWindowSeconds) ' sec'] , sprintf('Channel %d (avgI=%gDU)',1,mean(D.meanVec{1}))});            
            end
        else
            title(sprintf('Channel %d (avgI=%.1fDU)',channel_i,mean(D.meanVec{channel_i})));
        end

        ylims = get(gca,'YLim');
        for epoch_i=1:numel(taskStart)
            patch([taskStart(epoch_i)  taskStart(epoch_i)+taskDuration , taskStart(epoch_i)+taskDuration taskStart(epoch_i)],[ylims(1) ylims(1) ylims(2) ylims(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
        end
        set(gca,'YLim',ylims);
        set(gca,'XLim',[0 floor(timeVec_cut(end)) ]);
    end
    
    % Plot relative BFI
    subplot(Ny,Nx,(channel_i-1)*Nx+Nx);
    plot(timeVec_cut, avgBFI{channel_i}./median(avgBFI{channel_i}((1:round(secForNorm/dt)))) );
    xlabel('time [sec]');
    ylabel('rBFI ')
    if channel_i == 1
        if nOfChannels==1
            title({titleStart , ['rBFI with time filter of ' num2str(avgWindowSeconds) ' sec'] });
        else
            title({titleStart , ['rBFI with time filter of ' num2str(avgWindowSeconds) ' sec'] , 'Channel 1'});
        end
    else
        title(sprintf('Channel %d',channel_i));
    end
    
    ylims = get(gca,'YLim');
    for epoch_i=1:numel(taskStart)
        patch([taskStart(epoch_i)  taskStart(epoch_i)+taskDuration , taskStart(epoch_i)+taskDuration taskStart(epoch_i)],[ylims(1) ylims(1) ylims(2) ylims(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
    end
    set(gca,'YLim',ylims);
    set(gca,'XLim',[0 floor(timeVec_cut(end)) ]);
end

savefig(fig1,[recName '\averagedSignals_' num2str(avgWindowSeconds) 'sec_' savePrefix '.fig']);

%% Plot the epoches
fixed_ylim = [0.9 1.3];
if strcmp(taskName,'Verbal') || strcmp(taskName,'nBack') 
    fig2 = figure('Name',[ shortRecName ' '  titlePrefix ' Average ' num2str(avgWindowSeconds) ' Seconds' ],'Units','Normalized','Position',[0 0.8-nOfChannels*0.17 0.65 0.1+nOfChannels*0.17]);

    if plotOnlyBFI; Nx=1; else; Nx = 2; end

    for channel_i = 1:nOfChannels
        if ~plotOnlyBFI
            % plot relative Intensity for all epoches
            subplot(Ny,Nx,(channel_i-1)*Nx+1);
            plot(epochTime, avgOverEpoch{channel_i}.rI ,'b-','LineWidth',3);
            xlabel('time [sec]');
            ylabel('rI ');
            if channel_i == 1
                if nOfChannels==1
                    title({titleStart ,['relative Intensity average for ' num2str(numel(choose_epoches)) ' epoches (' num2str(avgWindowSeconds) ' sec filter)'] });
                else
                    title({titleStart ,['relative Intensity average for ' num2str(numel(choose_epoches)) ' epoches (' num2str(avgWindowSeconds) ' sec filter)'] , 'Channel 1'});
                end
            else
                title(sprintf('Channel %d',channel_i));
            end

            hold on
            if plotStd
                % plot std shaded line
                shadedErrorBar(epochTime,avgOverEpoch{channel_i}.rI,stdOverEpoch{channel_i}.rI,'lineprops',{'k-','LineWidth',3});
            else
                % plot each epoch as a line
                for eploch_i=1:size(epoch{channel_i}.rI,1)
                    plot(epochTime,epoch{channel_i}.rI(eploch_i,:),'k-');
                end
            end

            ylims = get(gca,'YLim');
            patch([0  taskDuration , taskDuration 0],[ylims(1) ylims(1) ylims(2) ylims(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
            set(gca,'YLim',ylims);
        end
        
        % plot relative BFI for all epoches
        subplot(Ny,Nx,(channel_i-1)*Nx+Nx);
%         plot(epochTime, 5,'b-','LineWidth',3); 
        hold on;
        xlabel('time [sec]');
        ylabel('rBFI ')
        if plotStd
            % plot std shaded line
            shadedErrorBar(epochTime,avgOverEpoch{channel_i}.rBFI,stdOverEpoch{channel_i}.rBFI,'lineprops',{'k-','LineWidth',3});
        else
            % plot each epoch as a line
            for eploch_i=1:size(epoch{channel_i}.rBFI,1)
                plot(epochTime,epoch{channel_i}.rBFI(eploch_i,:),'k-');
            end
        end
        if channel_i == 1
            if nOfChannels==1
                title({titleStart ,['rBFI average for ' num2str(numel(choose_epoches)) ' epoches (' num2str(avgWindowSeconds) ' sec filter)'] });
            else
                title({titleStart ,['rBFI average for ' num2str(numel(choose_epoches)) ' epoches (' num2str(avgWindowSeconds) ' sec filter)'] , 'Channel 1'});
            end
        else
            title(sprintf('Channel %d',channel_i));
        end
        grid on
        %     set(gca,'YLim',fixed_ylim);
        ylims = get(gca,'YLim');
        patch([0  taskDuration , taskDuration 0],[ylims(1) ylims(1) ylims(2) ylims(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
        plot([0 0], ylims , ':', taskDuration*[1 1],ylims,'--')
        set(gca,'YLim',ylims);
        set(gca,'FontSize',14)
        
    end
    savefig(fig2,[recName '\averagedSignals_EpochPlotAverage_' num2str(avgWindowSeconds) 'sec_' savePrefix '.fig']);
end
        
%% Save
originalSpeckleContrast = D.rawSpeckleContrast;
save([savePrefix '_averagedSignals_' num2str(avgWindowSeconds) 'sec.mat'],'avgI','avgBFI','originalSpeckleContrast','epochTime');