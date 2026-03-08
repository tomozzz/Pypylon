darkCurrentFolder = '.\Records\NoiseAndBackground\DarkCurrent';
origFolder = pwd;
cd(darkCurrentFolder)

oldStr = 'CoverTint';
newStr = 'Cover_Tint';
files = dir(['.\*' oldStr '*']);

for k = 1:numel(files)
    movefile(files(k).name,strrep(files(k).name,oldStr,newStr));
end

cd(origFolder)