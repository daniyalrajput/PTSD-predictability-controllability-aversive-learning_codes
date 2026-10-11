%% RATING-SCR BETA COUPLING AND SEPARATE MIXED ANOVAS
%
% PURPOSE: Analyze precomputed model-regressor coefficients for ratings and
% SCR. Compute Pearson correlations in 3 models x 2 conditions x 2 groups,
% compare independent group correlations via Fisher's z, and run separate
% Group x Condition x Model (2 x 2 x 3) mixed ANOVAs for each outcome.
% This script does not fit the original regressions.
%
% REQUIREMENTS: MATLAB R2020b+; Statistics and Machine Learning Toolbox.
% All local functions are included. Runtime execution remains unverified.
%
% INPUT: N Excel files, each with a header row and coefficients in column 1
% (configurable). Header names may differ. Rows MUST represent identical
% participant order across all files within each group. There are no IDs in
% this input format: alignment must be verified externally. Missing values
% must retain their rows; never independently delete/reorder input rows.
% Default positional truncation reproduces source minimum-length pairing.
% Disable it to require equal lengths; equal lengths still do not prove IDs.
%
% CLEANING: Correlations use finite paired rating/SCR rows, followed by
% optional single-pass +/-3 sample SD removal on either coefficient per
% group/model/condition. 
%
% STATISTICS: Correlation tests are two-sided, with Fisher-transform 95%
% intervals (N>3). Bonferroni families are fixed at 12 correlation tests and
% 6 independent group-comparison tests, including unavailable tests in the
% planned family sizes. Fisher comparisons require N>3 and |r|<1 in both
% groups.
%
% OUTPUT: Six scatterplots (model x condition), PNG and vector PDF; Excel
% master statistics with cleaned correlation pairs, ANOVA wide data and
% inclusion reports; optional MAT results. All plots share global axes and
% display each group's r, raw p and Bonferroni p.
% Author: Daniyal, University of Melbourne.

clear; clc; close all;

%% CONFIGURATION
inputDir = fullfile(pwd,'rating_scr_inputs');
outdir = fullfile(pwd,'rating_scr_outputs');
MODEL_NAMES = ["Surprise","Belief Uncertainty","Volatility"];
MODEL_TOKENS = ["surprise","belief_uncertainty","volatility"];
GROUP_LABELS = ["Group A","Group B"];
GROUP_TOKENS = ["group_a","group_b"];
CONDITION_LABELS = ["Controllable","Uncontrollable"];
OUTCOME_NAMES = ["Rating","SCR"];
OUTCOME_TOKENS = ["rating","scr"];
VALUE_COLUMN = 1;
SHEET = 1;
TRUNCATE_BY_ROW = true;
APPLY_3SD_CORR = true;
APPLY_3SD_ANOVA = true;
SD_THRESHOLD_CORR = 3;
SD_THRESHOLD_ANOVA = 3;
SAVE_CLEANED_EXCEL = true;
SAVE_MAT = true;
png_dpi = 600;
colors = zeros(2,3,2);
colors(:,:,1) = [0.05 0.20 0.55;0.60 0.10 0.10];
colors(:,:,2) = [0.38 0.68 0.95;0.92 0.62 0.62];
% Dimensions: group, condition, model, outcome.
inputFiles = strings(2,2,3,2);
for g = 1:2
    for c = 1:2
        for m = 1:3
            for o = 1:2
                inputFiles(g,c,m,o) = sprintf('%s_%s_%s_s%d.xlsx', ...
                    GROUP_TOKENS(g),OUTCOME_TOKENS(o),MODEL_TOKENS(m),c);
            end
        end
    end
end
assert(SD_THRESHOLD_CORR>0 && isfinite(SD_THRESHOLD_CORR),'Invalid correlation threshold.');
assert(SD_THRESHOLD_ANOVA>0 && isfinite(SD_THRESHOLD_ANOVA),'Invalid ANOVA threshold.');
if ~isfolder(outdir)
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory: %s',msg); end
end

%% READ ALL INPUTS; KEEP MISSING ROWS IN PLACE
raw = cell(2,2,3,2);
for k = 1:numel(inputFiles)
    file = fullfile(inputDir,inputFiles(k));
    if ~isfile(file), error('Missing input file: %s',file); end
    raw{k} = local_read_column(file,SHEET,VALUE_COLUMN);
end

%% TWELVE CORRELATION CELLS
pairs = cell(2,2,3);
corrStats = table(strings(12,1),strings(12,1),strings(12,1), ...
    zeros(12,1),nan(12,1),nan(12,1),nan(12,1),nan(12,1), ...
    nan(12,1),nan(12,1),nan(12,1),'VariableNames', ...
    {'Model','Condition','Group','N','r','CI_low','CI_high','t','df','p_raw','R2'});
corrAudit = table(); row = 0; allX = []; allY = [];
for m = 1:3
    for c = 1:2
        for g = 1:2
            rating = raw{g,c,m,1}; scr = raw{g,c,m,2};
            lengths = [numel(rating),numel(scr)];
            local_check_lengths(lengths,TRUNCATE_BY_ROW);
            n = min(lengths); Y = [scr(1:n),rating(1:n)];
            complete = all(isfinite(Y),2);
            outlier = false(n,1);
            if APPLY_3SD_CORR
                indices = find(complete);
                outlier(indices) = local_sd_outliers(Y(complete,:),SD_THRESHOLD_CORR);
            end
            keep = complete & ~outlier;
            pairs{g,c,m} = table(find(keep),Y(keep,1),Y(keep,2), ...
                'VariableNames',{'Aligned_row','Beta_SCR','Beta_Rating'});
            P = pairs{g,c,m};
            st = local_corr_stats(P.Beta_SCR,P.Beta_Rating);
            row = row+1;
            corrStats(row,:) = {MODEL_NAMES(m),CONDITION_LABELS(c),GROUP_LABELS(g), ...
                st.N,st.r,st.lo,st.hi,st.t,st.df,st.p,st.r^2};
            audit = table(repmat(MODEL_NAMES(m),n,1),repmat(CONDITION_LABELS(c),n,1), ...
                repmat(GROUP_LABELS(g),n,1),(1:n)',complete,outlier,keep, ...
                'VariableNames',{'Model','Condition','Group','Aligned_row', ...
                                'Complete_pair','Outlier_excluded','Retained'});
            corrAudit = [corrAudit;audit];
            allX = [allX;P.Beta_SCR]; allY = [allY;P.Beta_Rating];
            fprintf('%s | %s | %s: lengths=%s, retained=%d\n', ...
                MODEL_NAMES(m),CONDITION_LABELS(c),GROUP_LABELS(g),mat2str(lengths),st.N);
        end
    end
end
corrStats.p_bonf = min(corrStats.p_raw*12,1);
if isempty(allX), error('No finite correlation pairs remain.'); end
xlimits = local_limits(allX); ylimits = local_limits(allY);

%% SIX INDEPENDENT GROUP-CORRELATION COMPARISONS
compareStats = table(strings(6,1),strings(6,1),nan(6,1),zeros(6,1), ...
    nan(6,1),zeros(6,1),nan(6,1),nan(6,1),'VariableNames', ...
    {'Model','Condition','r_GroupA','N_GroupA','r_GroupB','N_GroupB','Fisher_z','p_raw'});
for m = 1:3
    for c = 1:2
        row = (m-1)*2+c; first = (m-1)*4+(c-1)*2+1;
        a = corrStats(first,:); b = corrStats(first+1,:);
        [z,p] = local_fisher_compare(a.r,a.N,b.r,b.N);
        compareStats(row,:) = {MODEL_NAMES(m),CONDITION_LABELS(c), ...
            a.r,a.N,b.r,b.N,z,p};
    end
end
compareStats.p_bonf = min(compareStats.p_raw*6,1);

%% SEPARATE RATING AND SCR MIXED ANOVAS
wide = cell(2,1); models = cell(2,1); withinStats = cell(2,1);
betweenStats = cell(2,1); anovaAudit = table();
responseNames = {'Surp_S1','Surp_S2','BU_S1','BU_S2','Vol_S1','Vol_S2'};
within = table(categorical(repelem(MODEL_NAMES(:),2)), ...
    categorical(repmat(["S1";"S2"],3,1)), ...
    'VariableNames',{'Model','Condition'});
for o = 1:2
    W = table();
    for g = 1:2
        lengths = zeros(1,6); vectors = cell(1,6);
        for m = 1:3
            for c = 1:2
                k = (m-1)*2+c; vectors{k} = raw{g,c,m,o};
                lengths(k) = numel(vectors{k});
            end
        end
        local_check_lengths(lengths,TRUNCATE_BY_ROW);
        n = min(lengths); Y = nan(n,6);
        for k = 1:6, Y(:,k) = vectors{k}(1:n); end
        Y(~isfinite(Y)) = NaN;
        complete = all(isfinite(Y),2); outlier = false(n,1);
        if APPLY_3SD_ANOVA
            outlier = local_sd_outliers(Y,SD_THRESHOLD_ANOVA);
        end
        keep = complete & ~outlier;
        if sum(keep) < 2
            error('Too few complete participants for %s ANOVA in %s.',OUTCOME_NAMES(o),GROUP_LABELS(g));
        end
        audit = table(repmat(OUTCOME_NAMES(o),n,1),repmat(GROUP_LABELS(g),n,1), ...
            (1:n)',complete,outlier,keep,'VariableNames', ...
            {'Outcome','Group','Aligned_row','Complete_case','Outlier_excluded','Retained'});
        anovaAudit = [anovaAudit;audit];
        labels = GROUP_TOKENS(g)+"_row"+string(find(keep));
        part = [table(labels,categorical(repmat(GROUP_LABELS(g),sum(keep),1)), ...
            'VariableNames',{'Subject','Group'}),array2table(Y(keep,:),'VariableNames',responseNames)];
        W = [W;part];
        fprintf('%s ANOVA | %s: lengths=%s, retained=%d\n', ...
            OUTCOME_NAMES(o),GROUP_LABELS(g),mat2str(lengths),sum(keep));
    end
    wide{o} = W;
    models{o} = fitrm(W,'Surp_S1-Vol_S2 ~ Group','WithinDesign',within);
    withinStats{o} = local_export_table(ranova(models{o},'WithinModel','Model*Condition'));
    betweenStats{o} = local_export_table(anova(models{o}));
end

%% SIX FIGURES; COMPUTE AND EXPORT EACH ONCE
for m = 1:3
    for c = 1:2
        fig = figure('Color','w','Units','pixels','Position',[100 100 1000 780]);
        ax = axes(fig); hold(ax,'on'); handles = gobjects(2,1);
        for g = 1:2
            P = pairs{g,c,m}; color = colors(g,:,c);
            handles(g) = scatter(ax,P.Beta_SCR,P.Beta_Rating,58,color,'filled', ...
                'MarkerEdgeColor','k','MarkerFaceAlpha',0.85);
            if height(P) >= 2 && std(P.Beta_SCR) > 0
                coef = polyfit(P.Beta_SCR,P.Beta_Rating,1);
                xx = linspace(min(P.Beta_SCR),max(P.Beta_SCR),100);
                plot(ax,xx,polyval(coef,xx),'Color',color,'LineWidth',2.2,'HandleVisibility','off');
            end
            row = (m-1)*4+(c-1)*2+g; st = corrStats(row,:);
            label = sprintf('%s: r = %.2f, p(raw) = %.3g, p(Bonf) = %.3g', ...
                GROUP_LABELS(g),st.r,st.p_raw,st.p_bonf);
            text(ax,0.02,0.98-(g-1)*0.055,label,'Units','normalized', ...
                'VerticalAlignment','top','FontSize',12,'Color',color,'Interpreter','none');
        end
        xlim(ax,xlimits); ylim(ax,ylimits);
        ax.XTick = linspace(xlimits(1),xlimits(2),4);
        ax.YTick = linspace(ylimits(1),ylimits(2),4);
        xtickformat(ax,'%.3g'); ytickformat(ax,'%.3g');
        ax.FontSize = 18; ax.LineWidth = 1.6; ax.TickDir = 'out'; ax.Box = 'off';
        xlabel(ax,'\beta_{SCR}','FontSize',26);
        ylabel(ax,'\beta_{Rating}','FontSize',26);
        title(ax,MODEL_NAMES(m)+" | "+CONDITION_LABELS(c),'FontSize',22);
        legend(ax,handles,cellstr(GROUP_LABELS),'Location','eastoutside','Box','off','FontSize',16);
        base = sprintf('Rating_SCR_%s_condition%d',MODEL_TOKENS(m),c);
        exportgraphics(fig,fullfile(outdir,[base,'.png']),'Resolution',png_dpi);
        exportgraphics(fig,fullfile(outdir,[base,'.pdf']),'ContentType','vector');
    end
end

%% MASTER RESULTS AND OPTIONAL CLEANED PAIRS
statsFile = fullfile(outdir,'Rating_SCR_Master_Statistics.xlsx');
writetable(corrStats,statsFile,'Sheet','Correlations');
writetable(compareStats,statsFile,'Sheet','Corr_group_comparisons');
writetable(corrAudit,statsFile,'Sheet','Correlation_inclusion');
writetable(anovaAudit,statsFile,'Sheet','ANOVA_inclusion');
for o = 1:2
    writetable(wide{o},statsFile,'Sheet',char("Wide_"+OUTCOME_NAMES(o)));
    writetable(withinStats{o},statsFile,'Sheet',char("ANOVA_"+OUTCOME_NAMES(o)));
    writetable(betweenStats{o},statsFile,'Sheet',char("Between_"+OUTCOME_NAMES(o)));
end
if SAVE_CLEANED_EXCEL
    cleanedPairs = table();
    for m = 1:3
        for c = 1:2
            for g = 1:2
                P = pairs{g,c,m}; n = height(P);
                part = [table(repmat(MODEL_NAMES(m),n,1),repmat(CONDITION_LABELS(c),n,1), ...
                    repmat(GROUP_LABELS(g),n,1),'VariableNames',{'Model','Condition','Group'}),P];
                cleanedPairs = [cleanedPairs;part];
            end
        end
    end
    writetable(cleanedPairs,statsFile,'Sheet','Cleaned_correlation_pairs');
end
if SAVE_MAT
    save(fullfile(outdir,'Rating_SCR_AllOutputs.mat'),'raw','pairs','corrStats', ...
        'compareStats','wide','models','within','withinStats','betweenStats', ...
        'corrAudit','anovaAudit','inputDir','inputFiles','MODEL_NAMES', ...
        'GROUP_LABELS','CONDITION_LABELS','OUTCOME_NAMES','VALUE_COLUMN','SHEET', ...
        'TRUNCATE_BY_ROW','APPLY_3SD_CORR','APPLY_3SD_ANOVA', ...
        'SD_THRESHOLD_CORR','SD_THRESHOLD_ANOVA','xlimits','ylimits');
end
fprintf('Completed. Master statistics: %s\n',statsFile);

%% LOCAL HELPERS
function x = local_read_column(file,sheet,column)
    T = readtable(file,'Sheet',sheet,'VariableNamingRule','preserve');
    if width(T) < column, error('Requested column missing in %s.',file); end
    raw = T{:,column};
    if isnumeric(raw), x = double(raw);
    else
        text = strtrim(string(raw)); x = str2double(text);
        bad = ~ismissing(text) & text ~= "" & isnan(x) & lower(text) ~= "nan";
        if any(bad), error('Nonnumeric coefficient in %s.',file); end
    end
    x = x(:); x(~isfinite(x)) = NaN;
end

function local_check_lengths(lengths,allowTruncation)
    if ~allowTruncation && numel(unique(lengths)) ~= 1
        error('Input lengths differ; align participants before running.');
    end
end

function flagged = local_sd_outliers(Y,threshold)
    flagged = false(size(Y,1),1);
    for k = 1:size(Y,2)
        x = Y(:,k); valid = isfinite(x);
        if sum(valid) < 2, continue; end
        mu = mean(x(valid)); sd = std(x(valid));
        if sd > 0, flagged = flagged | (valid & abs(x-mu) > threshold*sd); end
    end
end

function st = local_corr_stats(x,y)
    st = struct('N',numel(x),'r',NaN,'lo',NaN,'hi',NaN,'t',NaN,'df',NaN,'p',NaN);
    n = numel(x);
    if n < 3 || std(x)==0 || std(y)==0, return; end
    [r,p] = corr(x,y,'Type','Pearson'); r = max(-1,min(1,r));
    st.r = r; st.p = p; st.df = n-2;
    if abs(r)==1, st.t = sign(r)*Inf;
    else, st.t = r*sqrt((n-2)/(1-r^2)); end
    if n > 3
        if abs(r)==1, st.lo=r; st.hi=r;
        else
            delta = 1.959963984540054/sqrt(n-3);
            st.lo=tanh(atanh(r)-delta); st.hi=tanh(atanh(r)+delta);
        end
    end
end

function [z,p] = local_fisher_compare(r1,n1,r2,n2)
    z=NaN; p=NaN;
    if n1 <= 3 || n2 <= 3 || ~isfinite(r1) || ~isfinite(r2) || abs(r1)>=1 || abs(r2)>=1
        return;
    end
    z=(atanh(r1)-atanh(r2))/sqrt(1/(n1-3)+1/(n2-3));
    p=erfc(abs(z)/sqrt(2));
end

function limits = local_limits(x)
    low=min(x); high=max(x);
    if high==low, pad=max(0.01,0.06*max(1,abs(low)));
    else, pad=0.06*(high-low); end
    limits=[low-pad high+pad];
end

function T = local_export_table(T)
    names = string(T.Properties.RowNames);
    T = addvars(T,names,'Before',1,'NewVariableNames','Effect');
    T.Properties.RowNames = {};
end
