function  [rec, v] = Avi2Matrix(filename, nOfFrames, startFrame)
    
    % check input
    if ~exist('nOfFrames','var') || isempty(nOfFrames)
        nOfFrames = Inf;
    end
    
    if ~exist('startFrame','var') || isempty(startFrame)
        startFrame = 1;
    end

    if ~exist(filename,'file') == 2
        error(['"' filename '" does not exist !']);
    end
    
    if ~endsWith(filename,'.avi')
        error(['"' filename '" - Input filename should be an .avi file! ']);
    end
    
    % optn Video object
    v = VideoReader(filename);
    nOfFramesInRecord = round(v.Duration*v.FrameRate) ; % Not using the field 'NumFrames' because it is not consistent with different matlab versions
    %nOfFramesInRecord = v.NumFrames;
    
    %if isprop(v,'VideoFormat'); disp(v.VideoFormat); end%DEBUG

    % check if there is enough frames in record
    if ~isinf(nOfFrames) && (nOfFramesInRecord - startFrame + 1)  < nOfFrames
        error('No enough frames in the record "%s" \n Requested = %d ; Available = %d ( Frames in Record=%d; startFrame=%d )',...
            filename,nOfFrames,(nOfFramesInRecord - startFrame + 1), nOfFramesInRecord, startFrame);
    end

%     % set nOfFramesToRead
%     if ~isinf(nOfFrames)
%         nOfFramesToRead = nOfFrames ;
%     else
%         nOfFramesToRead = nOfFramesInRecord - startFrame + 1;    
%     end
    
    % Read 
%     rec  = zeros(v.Height,v.Width,nOfFramesToRead);
    v.CurrentTime =  startFrame/v.FrameRate ;
    im3color = read(v,[startFrame startFrame+nOfFrames-1]);
    rec = double( squeeze( im3color(:,:,1,:) ));
%     for i = 1:nOfFramesToRead
%         im3color = readFrame(v);
%         rec(:,:,i) = im3color(:,:,1); % all three colors are the same
%     end
