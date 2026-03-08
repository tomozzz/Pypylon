function recOut = PixFix(rec,BPmap)
    recOut = nan(size(rec));
    for frame = 1:size(rec,3)
        recOut(:,:,frame) = OneFramePixFix(rec(:,:,frame),BPmap);
    end    
end

function imOut = OneFramePixFix(im,BPmap)
    [yBP,xBP] = find(BPmap);
    imOut = im;
    for k=1:numel(xBP)
        % corners 
        if xBP(k) == 1 && yBP(k)==1
            arr = imOut(1:2,1:2); arr(1) = [];
        elseif xBP(k) == 1 && yBP(k) == size(im,1)
            arr = imOut(end-1:end,1:2); arr(2) = [];
        elseif xBP(k) == size(im,2) && yBP(k) == 1
            arr = imOut(1:2,end-1:end); arr(3) = [];
        elseif xBP(k) == size(im,2) && yBP(k) == size(im,1)
            arr = imOut(end-1:end,end-1:end); arr(4) = [];
        elseif yBP(k)==1 % first row
            arr = imOut(1:2,xBP(k)+(-1:1)); arr(3) = [];
        elseif yBP(k)==size(im,1) % last row
            arr = imOut(end-1:end,xBP(k)+(-1:1)); arr(4) = [];
        elseif xBP(k)==1 % first col
            arr = imOut(yBP(k)+(-1:1),1:2); arr(2) = [];
        elseif xBP(k)==size(im,2) % last col
            arr = imOut(yBP(k)+(-1:1),end-1:end); arr(5) = [];
        else   % standart case     
           arr = imOut(yBP(k)+(-1:1),xBP(k)+(-1:1)); arr(5) = [];                 
        end
        
        imOut(yBP(k),xBP(k)) = median(arr);
    end
end
