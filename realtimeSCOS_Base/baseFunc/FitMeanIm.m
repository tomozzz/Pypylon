function [A,B] = FitMeanIm(rec,mask,windowSize)
    A = ones(size(rec,1),size(rec,2));
    B = zeros(size(rec,1),size(rec,2));
    
    
    meanRec = nan(size(rec));
    meanMask = nan(1,size(rec,3));
    for i = 1:size(rec,3) % loop over frames
        im = rec(:,:,i);
        meanRec(:,:,i) = imfilter(im, true(windowSize)/windowSize^2,'conv','same');
        meanMask(i) = mean(im(mask)); 
    end    
    
    for x = 1:size(rec,2)
        for y = 1:size(rec,1)            
             p = polyfit(meanMask,meanRec(y,x,:),1);
             A(y,x) = p(1);
             B(y,x) = p(2);
        end
    end
end