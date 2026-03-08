function [fig1,fig2,avgBFI,avgK2,timeVec_cut]  = Calc_Averaged_rBFI(recName,avgWindowSeconds,titleAddText,useCorrected)

%% User Input
if ~exist('recName','var')    
    try load('lastFolder.mat'); catch ; end
    if ~exist('lastFolder','var'); lastFolder = '..\Records\Japan\OneChannel\1000micronFiber'; end
    recName = uigetdir(lastFolder);
    if recName == 0; return; end
    lastFolder = fileparts(recName);
    save('lastFolder.mat','lastFolder');
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
        avgWindowSeconds = 10;

    end
end

if ~exist('useCorrected','var')
    useCorrected = 0;
end
    
plotOnlyBFI = 1;

%% Parse user input

if contains(recName,'Hand','IgnoreCase',true)
    taskName = 'FingerGrip'; 
    titleTaskName = 'Fingers Grip Task'; 
    taskStart = 1*60; % 1sec
    taskDuration   = 2*60; % 3 sec
    taskColor = [1 0.65 0];
elseif contains(recName,'Verbal','IgnoreCase',true)
    taskName = 'Verbal'; 
    titleTaskName = 'Verbal Task';
%     taskDuration   = 40; %  0.5 minute
%     taskStart = 50 + 90*[0:3]; % each minut

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
matName = dir([recName '\LocalStd*.mat']);
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
epochTime = 0:dt:(secBeforeEpoch+taskDuration+secAfterEpoch);
indForRef = 1:round(secForRef/dt);
epoch = cell(1,nOfChannels);
avgOverEpoch = cell(1,nOfChannels);

for channel_i = 1:nOfChannels
    if ~useCorrected
        if isfield(D,'rawSpeckleContrast_jumpsCorrected') && numel(D.rawSpeckleContrast_jumpsCorrected)>=channel_i && ~isempty(D.rawSpeckleContrast_jumpsCorrected{channel_i})
            contrastVec=D.rawSpeckleContrast_jumpsCorrected{channel_i};
        else
            contrastVec=D.rawSpeckleContrast{channel_i};
        end
    else        
        contrastVec = D.corrSpeckleContrast{channel_i};
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
        for k=1:numel(taskStart)-1
            indStart = find(timeVec_cut >= taskStart(k)-secBeforeEpoch,1);
            indEnd   = indStart + numel(epochTime) - 1; %find(timeVec_cut >= taskStart(k)+taskDuration+secAfterEpoch,1);
            if indEnd > numel(avgI{channel_i})
                % pad the data 
                avgI{channel_i}(end+1:indEnd) = nan;
                avgBFI{channel_i}(end+1:indEnd) = nan;
                timeVec_cut(end+1:indEnd) = nan;
            end
            epoch{channel_i}.rI(k,:)   =  avgI{channel_i}(indStart:indEnd)./mean(avgI{channel_i}(indStart+indForRef));
            epoch{channel_i}.rBFI(k,:) =  avgBFI{channel_i}(indStart:indEnd)./mean(avgBFI{channel_i}(indStart+indForRef));
        end
        avgOverEpoch{channel_i}.rI = mean(epoch{channel_i}.rI,1,'omitnan');
        avgOverEpoch{channel_i}.rBFI = mean(epoch{channel_i}.rBFI,1,'omitnan');
    end
end

%%  Plot over all time
fig1 = figure('Name',[ shortRecName  'All record Average ' num2str(avgWindowSeconds) ' Seconds' ],'Units','Normalized','Position',[0 0.8-nOfChannels*0.17 0.3 0.1+nOfChannels*0.17]);
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
                title({titleStart ,['relative Intensity average over ' num2str(avgWindowSeconds) ' sec'] , 'Channel 1'});            
            end
        else
            title(sprintf('Channel %d',channel_i));
        end

        ylim = get(gca,'YLim');
        for k=1:numel(taskStart)
            patch([taskStart(k)  taskStart(k)+taskDuration , taskStart(k)+taskDuration taskStart(k)],[ylim(1) ylim(1) ylim(2) ylim(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
        end
        set(gca,'YLim',ylim);
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
    
    ylim = get(gca,'YLim');
    for k=1:numel(taskStart)
        patch([taskStart(k)  taskStart(k)+taskDuration , taskStart(k)+taskDuration taskStart(k)],[ylim(1) ylim(1) ylim(2) ylim(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
    end
    set(gca,'YLim',ylim);
    set(gca,'XLim',[0 floor(timeVec_cut(end)) ]);
end
savefig(fig1,[recName '\averagedSignals_' num2str(avgWindowSeconds) 'sec.fig']);

%% Plot the epoches
fixed_ylim = [0.9 1.3];
if strcmp(taskName,'Verbal') || strcmp(taskName,'nBack') 
    fig2 = figure('Name',[ shortRecName ' Apoch plot  Average ' num2str(avgWindowSeconds) ' Seconds' ],'Units','Normalized','Position',[0 0.8-nOfChannels*0.17 0.3 0.1+nOfChannels*0.17]);

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
                    title({titleStart ,['relative Intensity average for 5 epoches (' num2str(avgWindowSeconds) ' sec filter)'] });
                else
                    title({titleStart ,['relative Intensity average for 5 epoches (' num2str(avgWindowSeconds) ' sec filter)'] , 'Channel 1'});
                end
            else
                title(sprintf('Channel %d',channel_i));
            end

            hold on
            for eploch_i=1:size(epoch{channel_i}.rI,1) -1
                plot(epochTime,epoch{channel_i}.rI(eploch_i,:),'b-');
            end

            ylim = get(gca,'YLim');
            patch([secBeforeEpoch  secBeforeEpoch+taskDuration , secBeforeEpoch+taskDuration secBeforeEpoch],[ylim(1) ylim(1) ylim(2) ylim(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
            set(gca,'YLim',ylim);
        end
        
        % plot relative BFI for all epoches
        subplot(Ny,Nx,(channel_i-1)*Nx+Nx);
        plot(epochTime, avgOverEpoch{channel_i}.rBFI,'b-','LineWidth',3); 
        hold on;
        xlabel('time [sec]');
        ylabel('rBFI ')
        for eploch_i=1:size(epoch{channel_i}.rBFI,1)-1
            plot(epochTime,epoch{channel_i}.rBFI(eploch_i,:),'b-');
        end
        if channel_i == 1
            if nOfChannels==1
                title({titleStart ,['rBFI average for 5 epoches (' num2str(avgWindowSeconds) ' sec filter)'] });
            else
                title({titleStart ,['rBFI average for 5 epoches (' num2str(avgWindowSeconds) ' sec filter)'] , 'Channel 1'});
            end
        else
            title(sprintf('Channel %d',channel_i));
        end
        
        %     set(gca,'YLim',fixed_ylim);
        ylim = get(gca,'YLim');
        patch([secBeforeEpoch  secBeforeEpoch+taskDuration , secBeforeEpoch+taskDuration secBeforeEpoch],[ylim(1) ylim(1) ylim(2) ylim(2)], taskColor,'EdgeColor','none','FaceAlpha',0.15);
        set(gca,'YLim',ylim);
        
    end
    savefig(fig2,[recName '\averagedSignals_EpochPlotAverage_' num2str(avgWindowSeconds) 'sec.fig']);
end
        
%% Save
originalSpeckleContrast = D.rawSpeckleContrast;
save([recName '\averagedSignals_' num2str(avgWindowSeconds) 'sec.mat'],'avgI','avgBFI','originalSpeckleContrast');