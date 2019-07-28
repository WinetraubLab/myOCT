function awsWriteJSON(json,fp)
%This function write a JSON file from AWS or locally
%json - configuration file
%fp - file path

if (strcmpi(fp(1:3),'s3:'))
    %Load Data from AWS
    isAWS = true;
    fpToSave = 'tmp.json';
else
    isAWS = false;
    fpToSave = fp;
end

%Encode and save
txt = jsonencode(json);
txt = strrep(txt,'"',[newline '"']);
txt = strrep(txt,[newline '":'],'":');
txt = strrep(txt,[':' newline '"'],':"');
txt = strrep(txt,[newline '",'],'",');
fid = fopen(fpToSave,'w');
fprintf(fid,'%s',txt);
fclose(fid);

if (isAWS)
    %Upload if required
    awsCopyFileFolders(fpToSave,fp); 
    delete(fpToSave);
end