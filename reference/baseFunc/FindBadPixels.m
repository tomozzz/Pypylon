%% [totBP, spatialBP, temporalBP] = FindBadPixels(rec,thresholdSpatRel,thresholdTempRel, window)
%
%
%
%
%

function [totBP, spatialBP, temporalBP] = FindBadPixels(rec,threshSpatAbs,threshTempNumOfStd, threshTempAbs, window, plotFlag)
    rec = double(rec);
       
    if nargin < 3 || isempty(threshTempNumOfStd) % rellevant only if threshTempAbs is missing or empty
        threshTempNumOfStd = 5; %  num std above average
    end
    
    if nargin < 5 || isempty(window)
        window = 5;
    elseif window < 3 || window > 20
        error('window must be between 3 and 20');
    end
        
%% Temporal Bad Pixels
    if size(rec,3) < 2  %  3D
       temporalBP = false([size(rec,1) size(rec,2)]); 
    else
       if size(rec,3) < 10
           error('must have at least 10 frames for temporal bad pixels recognition');
       end
       
       tmpNoiseMat = std(rec,0,3);

       if exist('threshTempAbs','var') && ~isempty(threshTempAbs) % use absolute temporal noise value as a threshold
           temporalBP =  tmpNoiseMat > threshTempAbs;
       else % use fixed percentage of temporal bad pixels

%            [pdf,edges_pdf] = histcounts(tmpNoiseMat,1000);
%            figure; plot(edges_pdf(1:end-1) + diff(edges_pdf(1:2)/2) , pdf); title(['Temporal Noise , std = ' num2str(std(tmpNoiseMat(:)))]);

%            [cdf,edges] = histcounts(a,1000,'Normalization', 'cdf');
%            threshTempAbs = edges( find( cdf > (1-threshTempPercent) ,1 ));

           threshTempAbs = round( median(tmpNoiseMat(:)) + ( threshTempNumOfStd * std(tmpNoiseMat(:))) , 2 ) ;
           temporalBP =  tmpNoiseMat >  threshTempAbs ;
                      
       end
    end 

%% Spatial Bad Pixels

    im = mean(rec,3);
    hp_im = im - medfilt2(im,window*[1,1], 'symmetric' );
    
    if nargin < 2 || isempty(threshSpatAbs)
        threshSpatNumOfStd = 5;
        %threshSpatAbs = 0.09 * mean2(rec(:,:,1));
        threshSpatAbs = round(  threshSpatNumOfStd * std(hp_im(:)) , 1 ) ;
    end    
    
    spatialBP = abs(hp_im) > threshSpatAbs;
    
%% Total Bad Pixels Map
totBP = spatialBP | temporalBP ;

%% Plot
if exist('plotFlag','var') && plotFlag
    figure('Units','Normalized','Position',[0.1 0.1 0.7 0.5]);
    subplot(1,3,1); imshow(totBP);  title('Total Bad Pixels Map');
    subplot(1,3,2); imshow(spatialBP);  title({'Spatial Bad Pixels'  [ 'Threshold = ' num2str(threshSpatAbs) ' DU ' ]} );
    if size(rec,3) > 2
        subplot(1,3,3); imshow(temporalBP); title({'Temporal Bad Pixels', [ 'Threshold = ' num2str(threshTempAbs) ' DU '] });
        
       figure; histogram(tmpNoiseMat,500,'Normalization','pdf'); title('Temporal Noise Histogram');       
       hold on; plot(threshTempAbs*[1 1],get(gca,'Ylim'),'--r'); 
       xlabel('[DU]')
    end
    
    figure; histogram(hp_im,500,'Normalization','pdf'); title('Spatial Noise Histogram');
    hold on;  plot(threshSpatAbs*[1 1],get(gca,'Ylim'),'--r'); plot(-threshSpatAbs*[1 1],get(gca,'Ylim'),'--r'); 
end

%% Print
fprintf(' Bad Pixels \n------------\n')
fprintf('Spatial BP = %d \t( Threshold = %g DU)\n', nnz(spatialBP),threshSpatAbs);
if size(rec,3) > 2
    fprintf('Temporal BP = %d \t( Threshold = %g DU)\n',nnz(temporalBP), threshTempAbs);
end
fprintf('Total BP = %d \n',nnz(totBP));

end