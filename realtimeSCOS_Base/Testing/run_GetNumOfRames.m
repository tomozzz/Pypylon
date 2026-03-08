function out = run_GetNumOfRames(input,testingFolder)
% input struct must have one special variable called 'testingFolder' wich will be added to input.file_or_folder 
    out = struct();
    input.file_or_folder = fullfile(testingFolder, input.file_or_folder);
    if isfield(input,'MaxNOfFrames')
        if isfield(input,'parameters_names')
            if isfield(input,'parameters_expected_units')
                [out.Rec,out.parameters_names, out.parameters_values, out.parameters_units , out.info] = ...
                    ReadRecord(input.file_or_folder, input.MaxNOfFrames, input.parameters_names, input.parameters_expected_units);
            else
                [out.Rec,out.parameters_names, out.parameters_values, out.parameters_units , out.info] = ...
                    ReadRecord(input.file_or_folder, input.MaxNOfFrames, input.parameters_names);
            end
        else
            [out.Rec,out.parameters_names, out.parameters_values, out.parameters_units , out.info] = ...
                ReadRecord(input.file_or_folder, input.MaxNOfFrames);            
        end
    else
        [out.Rec,out.parameters_names, out.parameters_values, out.parameters_units , out.info] = ...
            ReadRecord(input.file_or_folder);
    end
end