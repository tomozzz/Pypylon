function out = run_ReadRecord(input,testingFolder)
% [rec, info] = ReadRecord( recName, nOfFrames , startFrame)

    out = struct();
    input.recName = fullfile(testingFolder, input.recName);
    if isfield(input,'nOfFrames')
        if isfield(input,'startFrame')
            [out.rec, out.info] = ReadRecord(input.recName, input.nOfFrames, input.startFrame);
        else
            [out.rec, out.info] = ReadRecord(input.recName, input.nOfFrames);            
        end
    else
        if isfield(input,'startFrame')
            [out.rec, out.info] = ReadRecord(input.recName , [] , input.startFrame);
        else
            [out.rec, out.info] = ReadRecord(input.recName ); 
        end
    end
end