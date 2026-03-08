function  [rec , nBits] = Tiff2Matrix(filename, nOfFrames, startFrame)
    if ~exist('startFrame','var') || isempty(startFrame)
        startFrame = 1;
    end
        
    if ~exist('nOfFrames','var') || isempty(nOfFrames) 
        nOfFrames = Inf;
    end
    
    nBits = nan;
    
    if exist(filename,'file') == 7  % its a folder
        tiff_files = dir([filename filesep '\*.tiff']) ;
        if ~isinf(nOfFrames)
            if numel(tiff_files) - startFrame + 1 < nOfFrames
                error('File "%s" -> There is no enough frames (requested: %d , in file starting from frame %d: %d) ',filename,nOfFrames,startFrame,numel(tiff_files) - startFrame + 1);
            end
        else
            nOfFrames = numel(tiff_files) - startFrame + 1;
        end
                
        % get first image in order to find out the image size
        t = Tiff(fullfile(filename,tiff_files(1).name),'r');
        rec = nan(getTag(t,'ImageLength'),getTag(t,'ImageWidth'),nOfFrames);
        nBits = getTag(t,'BitsPerSample');
        close(t);

        % read all images
        for k = 1:nOfFrames
            t = Tiff(fullfile(filename,tiff_files(k+startFrame-1).name),'r');
            rec(:,:,k) = read(t);
            close(t);
        end
    elseif exist(filename,'file') == 2 && ( endsWith(filename,'.tiff') || endsWith(filename,'.tif') ) % its a file
        % TBD need to check, and implement more efficiently
%         rec = tiffreadVolume(filename,'PixelRegion',{[1 Inf],[1 Inf],[ startFrame (startFrame+nOfFrames-1)]); %available from MATLAB 2020b

        t = Tiff(filename,'r');
% %         offsets = getTag(t,'SubIFD')
% %         setDirectory(t,k);
% %         setSubDirectory(t,offsets(k));
        rec = read(t);
        nBits = getTag(t,'BitsPerSample');
        close(t);
  
        if ~isinf(nOfFrames)
            rec = rec(:,:,startFrame:(nOfFrames+startFrame-1));
        elseif startFrame > 1
            rec = rec(:,:,startFrame:end);
        end
    end
    
    
end