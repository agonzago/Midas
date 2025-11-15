%%% Nowcasting %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This script produces a nowcast of EA real GDP growth for 2019:Q1 
% using the estimated parameters from a dynamic factor model.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% Clear workspace and set paths.
close all; clear; clc;
addpath('functions');


%% User inputs.
series = 'GDP' ; % Nowcasting Global real GDP (NGDPR) <GDS data>
period = '2019q4'; % Forecasting target quarter


%% Load model specification and first vintage of data.
% Load model specification structure `Spec`
Spec = load_spec('Spec_GL_Korea2.xls');

%% Load DFM estimation results structure `Res`.
Res = load('ResDFM'); % example_DFM.m used the first vintage of data for estimation


%% Update nowcast and decompose nowcast changes into news.

%%% Nowcast update from week of December 7 to week of December 16, 2016 %%%
vintage_old = '2019-10-02'; datafile_old = fullfile('data','Korea',[vintage_old '.xlsx']);
vintage_new = '2019-11-19'; datafile_new = fullfile('data','Korea',[vintage_new '.xlsx']);
% Load datasets for each vintage
[X_old,~   ] = load_data(datafile_old,Spec);
[X_new,Time] = load_data(datafile_new,Spec);

% check if spec used in estimation is consistent with the current spec
if isequal(Res.Spec,Spec)
    Res = Res.Res;
else
    threshold = 1e-4; % Set to 1e-5 for robust estimates
    Res = dfm(X_new,Spec,threshold);
    save('ResDFM','Res','Spec');
end 

update_nowcast(X_old,X_new,Time,Spec,Res,series,period,vintage_old,vintage_new);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



           