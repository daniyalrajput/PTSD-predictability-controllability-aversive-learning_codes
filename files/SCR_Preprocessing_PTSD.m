%% SINGLE-PARTICIPANT SCR PREPROCESSING: PTSD / GENERAL USE
% Requirements: MATLAB R2020b+ and Signal Processing Toolbox.
% Execution against participant recordings has not been verified.
%
% Change participantID, groupLabel, input filenames and paths below. Repeat
% separately for each participant and controllability condition. Group labels
% are metadata; preprocessing does not depend on diagnosis.
%
% INPUT EXCEL: Complete_Trials sheet, columns Block, event label, event time
% (indices 1,2,3). Each marker event must follow one fixation in the same
% block; their difference defines the window duration plus 2000 ms.
% INPUT MAT: data{1}.data = continuous SCR; data{2}.data = marker onsets;
% data{2}.markerinfo.name = one label per onset.
% RANGE EXCEL: Ranges_Sequential sheet; column 1 = Block1 ... Block10;
% column 2 = inclusive ORIGINAL trial ranges, e.g. 1:32. 
%
% PROCESSING: variable windows ending at each selected marker; crop first
% 4500 ms from each window's start; baseline first 1500 ms; zero-phase
% second-order high-pass 0.05 Hz then low-pass 5 Hz; global nonnegative shift,
% square root, and min-max scaling per trial (source default).
%
%
% FIXES: verify marker/window counts rather than truncate; convert times via
% configured sampling rate; distinguish rating markers from trial markers;
% reject nonpositive windows, out-of-recording onsets and repeated fixation
% use; baseline bounds cannot exceed the cropped window. All-missing/short
% signals remain NaN. Interpolate ONLY internal gaps in the finite span for
% filtering, restore original missing samples, never extrapolate edge padding.
%
% OUTPUTS: one MAT bundle containing every processing stage and configuration,
% Excel trial/marker/range summaries, and PNG/vector PDF diagnostic plots.
% Author: Daniyal, University of Melbourne

clear; clc; close all;

%% PARTICIPANT AND FILES
participantID = 'PS01_S1'; % PTSD example; use PS01_S2 for condition 2.
groupLabel = 'PTSD';
conditionLabel = 'Controllable'; % Set to 'Uncontrollable' for condition 2.
inputFolder = fullfile(pwd,'scr_preprocessing_inputs');
outputRoot = fullfile(pwd,'scr_preprocessing_outputs');
inputExcelFile = fullfile(inputFolder,['extr_',participantID,'_cleaned_trialchecked.xlsx']);
inputMatFile = fullfile(inputFolder,['ctrpspm_',participantID,'.mat']);
rangeExcelFile = fullfile(inputFolder,[participantID,'_TrialAnalysis.xlsx']);

%% DATA LAYOUT, TIMING AND MARKERS
EVENT_SHEET = 'Complete_Trials'; RANGE_SHEET = 'Ranges_Sequential';
BLOCK_COLUMN = 1; LABEL_COLUMN = 2; TIME_COLUMN = 3;
SCR_CHANNEL = 1; MARKER_CHANNEL = 2;
FS = 1000;
EVENT_TIME_UNITS = "milliseconds"; % Alternative: "seconds".
MARKER_ONSET_UNITS = "samples"; % Source convention; alternative: "seconds".
SAMPLE_INDEX_BASE = 1; % 1-based samples (source); use 0 for zero-based inputs.
% If onsets are seconds, t=0 maps to MATLAB sample index 1.
FIXATION_PATTERN = 'fixation'; % Case-insensitive regex for event labels.
EVENT_MARKER_PATTERN = 'marker';
STRESS_PATTERN = 'stress';
% Blank: select all non-rating markers. Otherwise regex selects trial labels.
% Set this to the trial marker naming convention in your recording if needed.
TRIAL_MARKER_PATTERN = '';
EXCLUDED_TRIALS = []; % ORIGINAL selected-trial indices, retained as NaN columns.
EXTRA_PREWINDOW_MS = 2000;
CROP_DURATION_MS = 4500;
BASELINE_DURATION_MS = 1500;
HIGH_PASS_HZ = 0.05; LOW_PASS_HZ = 5; FILTER_ORDER = 2;
RANGE_MODE = "trial"; % "trial" reproduces source; alternative: "session".
BLOCK_SETS = {["Block1","Block5","Block8","Block10"], ...
              ["Block3","Block4","Block7","Block9"],["Block2","Block6"]};
EARLY_BLOCKS = {["Block1","Block5"],["Block3","Block4"],"Block2"};
LATE_BLOCKS = {["Block8","Block10"],["Block7","Block9"],"Block6"};
PREDICTABILITY = ["HP","MP","UP"];
PNG_DPI = 300;

assert(FS>0&&isfinite(FS),'Invalid sampling rate.');
assert(0<HIGH_PASS_HZ&&HIGH_PASS_HZ<LOW_PASS_HZ&&LOW_PASS_HZ<FS/2,'Invalid filter frequencies.');
assert(ismember(RANGE_MODE,["trial","session"]),'Invalid range mode.');
assert(ismember(SAMPLE_INDEX_BASE,[0 1]),'Invalid sample index base.');
assert(BASELINE_DURATION_MS>0&&CROP_DURATION_MS>=BASELINE_DURATION_MS,'Invalid baseline/crop duration.');
assert(EXTRA_PREWINDOW_MS>=0&&isfinite(EXTRA_PREWINDOW_MS),'Invalid extra window duration.');
files={inputExcelFile,inputMatFile,rangeExcelFile};
for k=1:numel(files), assert(isfile(files{k}),'Missing input file: %s',files{k}); end
safeID=regexprep(participantID,'[^A-Za-z0-9_-]','_');
outputFolder=fullfile(outputRoot,[safeID,'_',datestr(now,'yyyymmdd_HHMMSS')]);
if isfolder(outputFolder)
    [~,suffix]=fileparts(tempname); outputFolder=[outputFolder,'_',suffix];
end
[ok,msg]=mkdir(outputFolder); assert(ok,'Cannot create output directory: %s',msg);

%% 1. EVENT WINDOWS: ONE MARKER PAIRED WITH ONE PRECEDING FIXATION
T=readtable(inputExcelFile,'Sheet',EVENT_SHEET,'VariableNamingRule','preserve');
assert(width(T)>=max([BLOCK_COLUMN,LABEL_COLUMN,TIME_COLUMN]),'Event table has insufficient columns.');
blocks=strtrim(string(T{:,BLOCK_COLUMN})); labels=string(T{:,LABEL_COLUMN});
eventTimes=local_numeric(T{:,TIME_COLUMN});
if EVENT_TIME_UNITS=="milliseconds", eventSeconds=eventTimes/1000;
elseif EVENT_TIME_UNITS=="seconds", eventSeconds=eventTimes;
else, error('Unknown event time units.'); end
markerRows=find(local_matches(labels,EVENT_MARKER_PATTERN));
assert(~isempty(markerRows),'No trial marker events found in the event table.');
fixationRows=nan(numel(markerRows),1); durations=fixationRows;
for i=1:numel(markerRows)
    m=markerRows(i);
    preceding=find(local_matches(labels(1:m-1),FIXATION_PATTERN),1,'last');
    assert(~isempty(preceding),'Marker event row %d has no preceding fixation.',m);
    assert(strcmpi(strtrim(blocks(preceding)),strtrim(blocks(m))), ...
        'Marker and fixation are in different blocks at event row %d.',m);
    fixationRows(i)=preceding; durations(i)=eventSeconds(m)-eventSeconds(preceding);
end
assert(numel(unique(fixationRows))==numel(fixationRows),'More than one marker was paired to the same fixation.');
assert(all(isfinite(durations)&durations>0),'Nonpositive or missing marker-fixation duration.');
windowSamples=round((durations+EXTRA_PREWINDOW_MS/1000)*FS);
window_table=table((1:numel(markerRows)).',blocks(markerRows),fixationRows,markerRows, ...
    durations,windowSamples,'VariableNames', ...
    {'Trial','Block','Fixation_event_row','Marker_event_row','Fixation_to_marker_seconds','Window_samples'});

%% 2. LOAD CONTINUOUS SCR AND MARKER METADATA
S=load(inputMatFile);
assert(isfield(S,'data')&&iscell(S.data)&&numel(S.data)>=max(SCR_CHANNEL,MARKER_CHANNEL), ...
    'MAT file must contain a data cell array with the configured channels.');
signal=double(S.data{SCR_CHANNEL}.data(:)); signal(~isfinite(signal))=NaN;
markerLabels=string(S.data{MARKER_CHANNEL}.markerinfo.name); markerLabels=markerLabels(:);
onsets=double(S.data{MARKER_CHANNEL}.data(:));
assert(numel(markerLabels)==numel(onsets),'Marker labels/onsets have different lengths.');
if MARKER_ONSET_UNITS=="samples", onsetSamples=round(onsets)+1-SAMPLE_INDEX_BASE;
elseif MARKER_ONSET_UNITS=="seconds", onsetSamples=round(onsets*FS)+1;
else, error('Unknown marker onset units.'); end
isStress=local_matches(markerLabels,STRESS_PATTERN);
selected=~isStress;
if ~isempty(TRIAL_MARKER_PATTERN), selected=selected&local_matches(markerLabels,TRIAL_MARKER_PATTERN); end
selectedMarkerIndices=find(selected);
assert(numel(selectedMarkerIndices)==height(window_table), ...
    ['Selected recording markers (%d) must equal event windows (%d). ' ...
     'Set TRIAL_MARKER_PATTERN and check both input files; no truncation is performed.'], ...
    numel(selectedMarkerIndices),height(window_table));
trialOnsets=onsetSamples(selected);
assert(all(isfinite(trialOnsets)&trialOnsets>=1&trialOnsets<=numel(signal)), ...
    'Trial onset outside the SCR recording; check marker units/index base.');
assert(all(diff(trialOnsets)>0),'Selected trial markers must be strictly chronological.');
nTrials=numel(trialOnsets);
assert(all(EXCLUDED_TRIALS==fix(EXCLUDED_TRIALS)&EXCLUDED_TRIALS>=1&EXCLUDED_TRIALS<=nTrials), ...
    'Excluded-trial indices are invalid.');
excluded=ismember((1:nTrials).',EXCLUDED_TRIALS);
stressLevel=nan(numel(onsets),1);
for i=find(isStress).'
    token=regexp(char(markerLabels(i)),'\(([-+]?\d*\.?\d+)\)','tokens','once');
    if ~isempty(token), stressLevel(i)=str2double(token{1}); end
end
marker_table=table((1:numel(onsets)).',markerLabels,onsets,onsetSamples,isStress,selected,stressLevel, ...
    'VariableNames',{'Marker_index','Label','Input_onset','Sample_index','Stress_marker','Selected_trial_marker','Stress_level'});

%% 3. SEGMENTS, CROPPING AND BASELINE
segments=nan(max(windowSamples),nTrials);
for i=1:nTrials
    if excluded(i), continue; end
    w=windowSamples(i); requestedStart=trialOnsets(i)-w+1;
    start=max(1,requestedStart); pad=start-requestedStart;
    segments(pad+1:w,i)=signal(start:trialOnsets(i));
end
cropSamples=min(round(CROP_DURATION_MS*FS/1000),size(segments,1));
baseSamples=round(BASELINE_DURATION_MS*FS/1000);
assert(baseSamples>=1&&baseSamples<=cropSamples,'Baseline exceeds available cropped window.');
segments_windowed=segments(1:cropSamples,:);
trial_baseline=mean(segments_windowed(1:baseSamples,:),1,'omitnan');
segments_corrected=segments_windowed-trial_baseline;

%% 4. ZERO-PHASE FILTERING WITH INTERNAL-GAP INTERPOLATION ONLY
[high_b,high_a]=butter(FILTER_ORDER,HIGH_PASS_HZ/(FS/2),'high');
[low_b,low_a]=butter(FILTER_ORDER,LOW_PASS_HZ/(FS/2),'low');
minFilterLength=3*(max([numel(high_b),numel(high_a),numel(low_b),numel(low_a)])-1)+1;
filtered_data=nan(size(segments_corrected));
filter_status=strings(nTrials,1); internal_missing=zeros(nTrials,1);
for i=1:nTrials
    td=segments_corrected(:,i); valid=find(isfinite(td));
    if excluded(i), filter_status(i)="Excluded by configuration"; continue; end
    if numel(valid)<2, filter_status(i)="Insufficient finite baseline-corrected samples"; continue; end
    span=(valid(1):valid(end)).';
    if numel(span)<minFilterLength, filter_status(i)="Finite span too short for filtfilt"; continue; end
    x=td(span); missing=~isfinite(x); internal_missing(i)=sum(missing);
    if any(missing), x(missing)=interp1(span(~missing),x(~missing),span(missing),'linear'); end
    x=filtfilt(high_b,high_a,x); x=filtfilt(low_b,low_a,x);
    x(missing)=NaN; filtered_data(span,i)=x; filter_status(i)="Processed";
end
assert(any(isfinite(filtered_data(:))),'No trials passed preprocessing; check signal, windows and baseline.');

%% 5. GLOBAL SHIFT, SQUARE ROOT AND EXPLICIT RANGE MODE
min_val=min(filtered_data(:),[],'omitnan');
shift=max(0,-min_val); filtered_data_sqrt=sqrt(filtered_data+shift);
filtered_data_range_corrected=nan(size(filtered_data_sqrt));
if RANGE_MODE=="session"
    lo=min(filtered_data_sqrt(:),[],'omitnan'); hi=max(filtered_data_sqrt(:),[],'omitnan');
    if hi>lo, filtered_data_range_corrected=(filtered_data_sqrt-lo)/(hi-lo);
    else, filtered_data_range_corrected(isfinite(filtered_data_sqrt))=0; end
else
    for i=1:nTrials
        x=filtered_data_sqrt(:,i); valid=isfinite(x);
        if ~any(valid), continue; end
        lo=min(x(valid)); hi=max(x(valid));
        if hi>lo, filtered_data_range_corrected(valid,i)=(x(valid)-lo)/(hi-lo);
        else, filtered_data_range_corrected(valid,i)=0; end
    end
end

%% 6. ORIGINAL BLOCK RANGES, WITH NO TRIAL DELETION OR RANGE SHIFTS
R=readtable(rangeExcelFile,'Sheet',RANGE_SHEET,'VariableNamingRule','preserve');
assert(width(R)>=2,'Range table needs block and inclusive range columns.');
blockNames=strtrim(string(R{:,1})); rangeStrings=strtrim(string(R{:,2}));
assert(numel(unique(lower(blockNames)))==numel(blockNames),'Duplicate block names in range table.');
trialBlock=strings(nTrials,1); block_data=struct();
for i=1:height(R)
    token=regexp(char(rangeStrings(i)),'^(\d+)\s*:\s*(\d+)$','tokens','once');
    assert(~isempty(token),'Invalid range for %s: %s',blockNames(i),rangeStrings(i));
    first=str2double(token{1}); last=str2double(token{2});
    assert(first>=1&&last<=nTrials&&last>=first,'Out-of-bounds range for %s.',blockNames(i));
    ix=first:last; assert(all(trialBlock(ix)==""),'Overlapping range for %s.',blockNames(i));
    trialBlock(ix)=blockNames(i);
    field=matlab.lang.makeValidName(char(blockNames(i)));
    assert(~isfield(block_data,field),'Block names collide after conversion: %s',blockNames(i));
    block_data.(field)=filtered_data_range_corrected(:,ix);
end
assert(all(trialBlock~=""),'Range table must cover every original trial.');
assert(all(strcmpi(trialBlock,window_table.Block)), ...
    'Event block labels disagree with original block ranges; check participant files or trial order.');

%% 7. PREDICTABILITY AND EARLY/LATE TRIAL POOLS
predictability_groups=struct(); early_groups=struct(); late_groups=struct();
mean_predictability=nan(cropSamples,3); mean_early=mean_predictability; mean_late=mean_predictability;
counts=zeros(3,3);
for p=1:3
    allMask=local_block_mask(trialBlock,BLOCK_SETS{p});
    earlyMask=local_block_mask(trialBlock,EARLY_BLOCKS{p}); lateMask=local_block_mask(trialBlock,LATE_BLOCKS{p});
    assert(any(allMask)&&any(earlyMask)&&any(lateMask),'Missing required blocks for %s.',PREDICTABILITY(p));
    key=char(PREDICTABILITY(p));
    predictability_groups.(key)=filtered_data_range_corrected(:,allMask);
    early_groups.(key)=filtered_data_range_corrected(:,earlyMask);
    late_groups.(key)=filtered_data_range_corrected(:,lateMask);
    mean_predictability(:,p)=mean(predictability_groups.(key),2,'omitnan');
    mean_early(:,p)=mean(early_groups.(key),2,'omitnan');
    mean_late(:,p)=mean(late_groups.(key),2,'omitnan');
    counts(p,:)=[sum(allMask),sum(earlyMask),sum(lateMask)];
end
time_seconds=(0:cropSamples-1).'/FS;
trial_table=[window_table,table(selectedMarkerIndices,trialOnsets,excluded,trial_baseline(:), ...
    sum(isfinite(segments_windowed),1).',internal_missing,filter_status, ...
    'VariableNames',{'Recording_marker_index','Onset_sample','Excluded','Baseline', ...
    'Finite_cropped_samples','Internal_gap_samples','Filter_status'})];
condition_summary=table(PREDICTABILITY(:),counts(:,1),counts(:,2),counts(:,3), ...
    'VariableNames',{'Predictability','Trials_all','Trials_early','Trials_late'});

%% 8. DIAGNOSTIC FIGURES
local_plot_pair(time_seconds,segments_windowed,segments_corrected,'Windowed SCR','Baseline corrected', ...
    outputFolder,[safeID,'_BaselineCorrection'],PNG_DPI);
local_plot_pair(time_seconds,segments_corrected,filtered_data,'Before filter','After filter', ...
    outputFolder,[safeID,'_Filtering'],PNG_DPI);
local_plot_pair(time_seconds,filtered_data_sqrt,filtered_data_range_corrected,'Square root','Range corrected', ...
    outputFolder,[safeID,'_Transformations'],PNG_DPI);
fig=figure('Color','w'); ax=axes(fig);
plot(ax,time_seconds,mean_predictability,'LineWidth',2);
xlabel(ax,'Time from window start (s)'); ylabel(ax,'SCR (sqrt, range-corrected)');
title(ax,[participantID,' | ',groupLabel,' | ',conditionLabel],'Interpreter','none');
legend(ax,cellstr(PREDICTABILITY),'Location','best'); grid(ax,'on');
local_save_figure(fig,outputFolder,[safeID,'_PredictabilityMeans'],PNG_DPI);
fig=figure('Color','w','Position',[100 100 1200 500]); t=tiledlayout(1,2);
ax=nexttile(t); plot(ax,time_seconds,mean_early,'LineWidth',2); title(ax,'Early blocks');
xlabel(ax,'Time from window start (s)'); ylabel(ax,'SCR (sqrt, range-corrected)');
legend(ax,cellstr(PREDICTABILITY)); grid(ax,'on');
ax=nexttile(t); plot(ax,time_seconds,mean_late,'LineWidth',2); title(ax,'Late blocks');
xlabel(ax,'Time from window start (s)'); ylabel(ax,'SCR (sqrt, range-corrected)');
legend(ax,cellstr(PREDICTABILITY)); grid(ax,'on');
local_save_figure(fig,outputFolder,[safeID,'_EarlyLateMeans'],PNG_DPI);

%% 9. SAVE ALL STAGES AND CONFIGURATION
config=struct('Participant',participantID,'Group',groupLabel,'Condition',conditionLabel, ...
    'InputEvents',inputExcelFile,'InputSCR',inputMatFile,'InputRanges',rangeExcelFile, ...
    'FS',FS,'EventTimeUnits',EVENT_TIME_UNITS,'MarkerOnsetUnits',MARKER_ONSET_UNITS, ...
    'SampleIndexBase',SAMPLE_INDEX_BASE,'SCRChannel',SCR_CHANNEL,'MarkerChannel',MARKER_CHANNEL, ...
    'EventSheet',EVENT_SHEET,'RangeSheet',RANGE_SHEET,'BlockColumn',BLOCK_COLUMN, ...
    'EventLabelColumn',LABEL_COLUMN,'EventTimeColumn',TIME_COLUMN, ...
    'TrialMarkerPattern',TRIAL_MARKER_PATTERN,'EventMarkerPattern',EVENT_MARKER_PATTERN, ...
    'FixationPattern',FIXATION_PATTERN,'StressPattern',STRESS_PATTERN,'ExcludedTrials',EXCLUDED_TRIALS, ...
    'ExtraPrewindowMs',EXTRA_PREWINDOW_MS,'CropDurationMs',CROP_DURATION_MS, ...
    'BaselineDurationMs',BASELINE_DURATION_MS,'HighPassHz',HIGH_PASS_HZ,'LowPassHz',LOW_PASS_HZ, ...
    'FilterOrder',FILTER_ORDER,'RangeMode',RANGE_MODE,'NonnegativeShift',shift);
summaryFile=fullfile(outputFolder,[safeID,'_Preprocessing.xlsx']);
writetable(trial_table,summaryFile,'Sheet','Trials');
writetable(marker_table,summaryFile,'Sheet','All_markers');
writetable(marker_table(isStress,:),summaryFile,'Sheet','Stress_markers');
writetable(R,summaryFile,'Sheet','Original_block_ranges');
writetable(condition_summary,summaryFile,'Sheet','Predictability_counts');
save(fullfile(outputFolder,[safeID,'_AllPreprocessing.mat']),'config','signal','marker_table', ...
    'window_table','trial_table','R','segments','segments_windowed','trial_baseline','segments_corrected', ...
    'filtered_data','filtered_data_sqrt','filtered_data_range_corrected','block_data', ...
    'predictability_groups','early_groups','late_groups','mean_predictability','mean_early','mean_late', ...
    'time_seconds','condition_summary','BLOCK_SETS','EARLY_BLOCKS','LATE_BLOCKS','-v7.3');
fprintf('Completed %s (%s). Processed %d/%d trials. Outputs: %s\n', ...
    participantID,groupLabel,sum(filter_status=="Processed"),nTrials,outputFolder);

%% HELPERS
function x=local_numeric(raw)
    if isnumeric(raw), x=double(raw(:));
    else, x=str2double(string(raw(:))); end
end
function mask=local_matches(labels,pattern)
    mask=false(numel(labels),1);
    for k=1:numel(labels)
        if ~ismissing(labels(k)), mask(k)=~isempty(regexpi(char(labels(k)),pattern,'once')); end
    end
end
function mask=local_block_mask(blocks,desired)
    mask=ismember(lower(strtrim(blocks)),lower(strtrim(string(desired))));
end
function local_plot_pair(time,A,B,titleA,titleB,folder,name,dpi)
    fig=figure('Color','w'); t=tiledlayout(2,1);
    ax=nexttile(t); plot(ax,time,A); title(ax,titleA); xlabel(ax,'Time from window start (s)'); grid(ax,'on');
    ax=nexttile(t); plot(ax,time,B); title(ax,titleB); xlabel(ax,'Time from window start (s)'); grid(ax,'on');
    local_save_figure(fig,folder,name,dpi);
end
function local_save_figure(fig,folder,name,dpi)
    exportgraphics(fig,fullfile(folder,[name,'.png']),'Resolution',dpi);
    exportgraphics(fig,fullfile(folder,[name,'.pdf']),'ContentType','vector');
end
