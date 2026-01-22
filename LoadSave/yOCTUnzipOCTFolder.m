function yOCTUnzipOCTFolder(OCTFolderZipFileIn,OCTFolderOut,isDeleteOCTZippedFile)
%This function unzips .oct file (OCTFolderZipFileIn) into OCTFolderOut, and
%deletes OCTFolderZipFileIn (default)

%% Make sure we have AWS Cridentials
if (strcmpi(OCTFolderZipFileIn(1:3),'s3:'))
    awsSetCredentials (1); %Write cridentials are required  
    OCTFolderZipFileIn = awsModifyPathForCompetability(OCTFolderZipFileIn,true);
    isAWSIn = true;
else
    isAWSIn = false;
end
if (awsIsAWSPath(OCTFolderOut))
    awsSetCredentials (1); %Write cridentials are required
    OCTFolderOut = awsModifyPathForCompetability(OCTFolderOut,true);
    isAWSOut = true;
else
    isAWSOut = false;
end

if ~exist('isDeleteOCTZippedFile','var')
    isDeleteOCTZippedFile = true;
end

%% Setup input directory
if (isAWSIn)
    %We will need to unzip file locally

    %Download file from AWS
    system(['aws s3 cp "' OCTFolderZipFileIn '" tmp.oct']);

    if ~exist('tmp.oct','file')
        error('File did not download from AWS');
    end
    
    OCTFolderZipFileInOrig = OCTFolderZipFileIn;
    OCTFolderZipFileIn = 'tmp.oct';
end

%% Setup output directory
OCTUnzipToDirectory = OCTFolderOut;
if (isAWSOut)
    %Destination is at the cloud, need to unzip locally
    OCTUnzipToDirectory = 'tmp';
end
if strcmp(OCTFolderOut(1:2),'\\')
    %We are trying to unzip to a netowrk dirve, this is not a good idea
    %so we shall unzip to a local drive, than move to network drive
    OCTUnzipToDirectory = 'tmp';
end

%Check Unziped to directory is empty
%if exist(OCTUnzipToDirectory,'dir')
    %Delete directory first
%    rmdir(OCTUnzipToDirectory,'s');
%end

%% Preform Unzip

% Clean destination directory content if it exists (keeping the .oct file)
% This allows re-decompression when needed (example: after failed extraction or corrupted files)
if exist(OCTUnzipToDirectory,'dir')
    % Only delete data folder and extracted files, not the .oct itself
    dataFolderToClean = fullfile(OCTUnzipToDirectory, 'data');
    if exist(dataFolderToClean, 'dir')
        rmdir(dataFolderToClean, 's');
    end
    
    % Delete any data* files from previous failed extractions
    oldFiles = dir(fullfile(OCTUnzipToDirectory, 'data*'));
    for i = 1:length(oldFiles)
        if ~oldFiles(i).isdir
            delete(fullfile(OCTUnzipToDirectory, oldFiles(i).name));
        end
    end
end

%Unzip using 7-zip
if exist('C:\Program Files\7-Zip\','dir')
    z7Path = 'C:\Program Files\7-Zip\';
elseif exist('C:\Program Files (x86)\7-Zip\','dir')
    z7Path ='C:\Program Files (x86)\7-Zip\';
else
    error('Please Install 7-Zip');
end
system(['"' z7Path '7z.exe" x "' OCTFolderZipFileIn '" -o"' OCTUnzipToDirectory '" -aos']);

%Check unzip was successfull
if ~exist(OCTUnzipToDirectory,'dir')
    error('Failed to Unzip');
end

%% Fix malformed file names (data·Chirp.data -> data/Chirp.data)
% Some .oct files store paths with middle dot (·) instead of directory separator
% This fixes the structure by creating proper data/ folder and moving files
dataFolder = fullfile(OCTUnzipToDirectory, 'data');
if ~exist(dataFolder, 'dir')
    % data folder doesn't exist, check for malformed files
    files = dir(OCTUnzipToDirectory);
    filesToMove = {};
    
    for i = 1:length(files)
        fname = files(i).name;
        % Skip . and ..
        if strcmp(fname, '.') || strcmp(fname, '..')
            continue;
        end
        
        % Check if file starts with "data" and contains non-standard separator
        if ~files(i).isdir && length(fname) > 4 && strcmp(fname(1:4), 'data')
            % Check if character after "data" is NOT a normal separator
            if fname(5) ~= '.' && fname(5) ~= '_' && fname(5) ~= '-'
                % This is a malformed file: data[weird char]filename.data
                filesToMove{end+1} = fname; %#ok<AGROW>
            end
        end
    end
    
    if ~isempty(filesToMove)
        % Create data folder and move files for malformed names (data·Chirp.data to data/Chirp.data)
        % This is normal behavior for some 7-Zip versions that don't preserve directory structure
        mkdir(dataFolder);
        
        % Move all malformed files to data folder, removing 'data·' prefix
        for i = 1:length(filesToMove)
            oldName = fullfile(OCTUnzipToDirectory, filesToMove{i});
            % Remove first 5 characters: "data" + weird separator
            newFileName = filesToMove{i}(6:end);
            newName = fullfile(dataFolder, newFileName);
            movefile(oldName, newName);
        end
    end
end

if exist('OCTFolderZipFileInOrig','var')
    %OCTFolderZipFileIn is actually a temp file, delete it 
    delete(OCTFolderZipFileIn);
    OCTFolderZipFileIn = OCTFolderZipFileInOrig;
end

%% Upload if necessary
if ~strcmp(OCTUnzipToDirectory,OCTFolderOut)
    %Unzipped directory different from output folder, it means we need to
    %upload
    if(isAWSOut)
        %Upload to bucket
        awsCopyFileFolder(OCTUnzipToDirectory,OCTFolderOut);
        
        %Cleanup, delete temporary directory
        rmdir(OCTUnzipToDirectory,'s'); 
    else
        %File system copy
        movefile(OCTUnzipToDirectory,OCTFolderOut,'f');
    end
end

%% Remove zipped archive if required (.OCT file)
% Only delete if unzip was successful (Header.xml exists in data folder)
if isDeleteOCTZippedFile
    % Verify unzip was successful before deleting source
    % Check in the final destination (OCTFolderOut, not temp directory)
    headerCheck = fullfile(OCTFolderOut, 'data', 'Header.xml');
    if ~awsExist(headerCheck, 'file')
        % Also check without data/ subfolder (in case structure is flat)
        headerCheck = fullfile(OCTFolderOut, 'Header.xml');
    end
    
    if awsExist(headerCheck, 'file')
        % Success: safe to delete compressed file
        if (isAWSIn)
            system(['aws s3 rm "' OCTFolderZipFileIn '"']);
        else
            delete(OCTFolderZipFileIn);
        end
    end
end