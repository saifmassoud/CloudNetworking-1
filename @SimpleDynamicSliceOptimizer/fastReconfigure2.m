%% Fast Reconfiguration with VNF Instance Re-scaling
% Comparing with <_fastReconfigure_>, this method also considers VNF instance re-scaling,
% i.e., the capacity of VNF instances could change during reconfiguration.
% See also <fastReconfigure>.
function [profit,cost] = fastReconfigure2(this, action, new_opts)
global DEBUG; %#ok<NUSED>

if nargin <= 2
    new_opts = struct;
end
options = structmerge(new_opts, ...
    getstructfields(this.Parent.options, 'Form', 'default', {'normal'}), ...
    getstructfields(this.options, 'PricingPolicy', 'default', {'quadratic'}), ...
    getstructfields(this.options, 'ReconfigMethod'),...
    'exclude');   

if this.NumberFlows == 0
    [profit, cost] = this.handle_zero_flow(options);
    return;
end

NL = this.NumberLinks;
NN = this.NumberServiceNodes;
NP = this.NumberPaths;
NV = this.NumberVNFs;

%%% Formulate input for convex optimization (fmincon).
% The problem has multiple inequalities, and the lowerbounds for variables.
As_res = this.As_res;        % update As_res
%% Save the VNF capacity to the previous state, berfore optimization
% 'FastReconfig2' reconfigure VNF instance. After the slice is created, |VNFCapacity| is recorded.
% After each optimization, the |VNFCapacity| is updated.
this.old_variables.v = this.Variables.v;  
this.update_reconfig_costvinfo();              % update reconfigure cost with scaler.
%%
% List of constraints:
%   (1) flow processing requirement: NP*NV (this.NumberLinearConstraints);
%   (2) VNF instance capacity constraint: NV*NN (this.num_varv); VNF load
%       (y_nf) is no more than VNF instance capacity (v_nf);
%   (3) Node capacity constraint: NN; VNF instance capacity is no more than
%       node capacity. Since there is reconfiguration cost, we cannot use
%       VNF load to express the constraint (Hrep*z). Instead we directly
%       use VNF instance capacity as variables to express it
%       (sum(v_nf)<=v_n). See also <Slice.getHrep>. 
%   (4) Link capacity constraint: NL;
%   (5) link reconfiguration cost constraint: 2*NP;
%   (6) node reconfiguration cost constraint: 2*NN*NP*NV (2*this.num_varz);
%   (5) VNF instance reconfiguration cost constraint: 2*NV*NN;
num_lcon = this.NumberLinearConstraints + this.num_varv + NN + NL + ...
    2*NP + 2*this.num_varz + 2*this.num_varv;
nnz_As = nnz(As_res) + (nnz(this.Hdiag)+this.num_varv) + nnz(this.Hrep) + nnz(this.I_edge_path) + ...
    + 4*NP + 4*this.num_varz+ 4*this.num_varv;
num_vars = 2*this.NumberVariables + 2*this.num_varv;
As = spalloc(num_lcon, num_vars, nnz_As);
As(1:this.NumberLinearConstraints,1:this.NumberVariables) = As_res;
row_offset = this.NumberLinearConstraints;
As(row_offset+(1:this.num_varv), NP+(1:this.num_varz)) = this.Hdiag;
As(row_offset+(1:this.num_varv), this.NumberVariables+(1:this.num_varv)) = -eye(this.num_varv);
row_offset = row_offset + this.num_varv;
As(row_offset+(1:NN), this.NumberVariables+(1:this.num_varv)) = repmat(eye(NN),1,NV);
row_offset = row_offset + NN;
As(row_offset+(1:NL), 1:NP) = this.I_edge_path;
row_offset = row_offset + NL;
As(row_offset+(1:NP), 1:NP) = eye(NP);
As(row_offset+(1:NP), num_vars/2+(1:NP)) = -eye(NP);
row_offset = row_offset + NP;
As(row_offset+(1:NP), 1:NP) = -eye(NP);
As(row_offset+(1:NP), num_vars/2+(1:NP)) = -eye(NP);
row_offset = row_offset + NP;
As(row_offset+(1:this.num_varz), (NP+1):this.NumberVariables) = eye(this.num_varz);
As(row_offset+(1:this.num_varz), (num_vars/2+NP)+(1:this.num_varz)) = -eye(this.num_varz);
row_offset = row_offset + this.num_varz;
As(row_offset+(1:this.num_varz), (NP+1):this.NumberVariables) = -eye(this.num_varz);
As(row_offset+(1:this.num_varz), (num_vars/2+NP)+(1:this.num_varz)) = -eye(this.num_varz);
row_offset = row_offset + this.num_varz;
As(row_offset+(1:this.num_varv), (this.NumberVariables+1):num_vars/2) = eye(this.num_varv);
As(row_offset+(1:this.num_varv), (num_vars/2+this.NumberVariables+1):end) = -eye(this.num_varv);
row_offset = row_offset + this.num_varv;
As(row_offset+(1:this.num_varv), (this.NumberVariables+1):num_vars/2) = -eye(this.num_varv);
As(row_offset+(1:this.num_varv), (num_vars/2+this.NumberVariables+1):end) = -eye(this.num_varv);

bs = [sparse(this.NumberLinearConstraints+this.num_varv,1);
    this.ServiceNodes.Capacity; % The field will only change in slice dimensionging.
    this.Links.Capacity;
    this.topts.old_variables_x;       % which have been pre-processed, so it can be
    -this.topts.old_variables_x;      % compared with the current states.
    this.topts.old_variables_z;
    -this.topts.old_variables_z;
    this.old_variables.v;      % Equal to last stage's VNF capacity, size not change
    -this.old_variables.v];

var0 = [this.topts.old_variables_x;
    this.topts.old_variables_z;
    this.old_variables.v;
    %     this.topts.old_variables_x;
    %     this.topts.old_variables_z;
    %     this.old_variables.v
    zeros(this.NumberVariables+this.num_varv,1)
    ];
assert(this.checkFeasible(var0), 'error: infeasible start point.');

%% Perform optimization
fmincon_opt = optimoptions(@fmincon);
fmincon_opt.Algorithm = 'interior-point';
fmincon_opt.SpecifyObjectiveGradient = true;
fmincon_opt.Display = 'notify';
if strcmpi(options.Form, 'compact')
    %% get the compact formulation
    % There are lots of zeros in $z_npf$, which could be determined by $h_np$.
    % If a row is all zero, this row is in-active, and could be removed.
    z_filter = sparse(repmat(...
        reshape(logical(this.I_node_path), numel(this.I_node_path),1),...
        NV,1));
    this.I_active_variables = [true(NP,1);  z_filter;  true(this.num_varv,1);...
        true(NP,1); z_filter; true(this.num_varv,1)];
    row_offset = this.NumberLinearConstraints + this.num_varv + NN + NL + 2*NP;
    active_rows = [(1:row_offset)'; row_offset+find(z_filter); ...
        row_offset+this.num_varz+find(z_filter); ...
        ((num_lcon-2*this.num_varv+1):num_lcon)'];
    As = As(active_rows, this.I_active_variables);
    var0 = var0(this.I_active_variables);
    bs = bs(active_rows);
    fcn_opts.num_varz = nnz(z_filter);
    this.topts.z_reconfig_cost = this.topts.z_reconfig_cost(z_filter);
    fcn_opts.bCompact = true;
else
    fcn_opts.num_varz = this.num_varz;
end
lbs = sparse(length(var0),1);
fcn_opts.num_varx = this.NumberPaths;
fcn_opts.num_varv = this.num_varv;
fmincon_opt.HessianFcn = ...
    @(x,lambda)DynamicSlice.hessReconfigure(x, lambda, this, fcn_opts);
[xs, fval, exitflag, output] = ...
    fmincon(@(x)DynamicSlice.fcnFastConfigProfit(x, this, fcn_opts), ...
    var0, As, bs, [], [], lbs, [], [], fmincon_opt);
if strcmpi(options.Form, 'compact')
    x = zeros(num_vars, 1);
    x(this.I_active_variables) = xs;
else
    x = xs;
end

%% Reconfiguration Cost in Problem Formulation
% comparing the old variables with new variables to decide the reconfiguration
% cost.
% Since the two vector has different number of elements, we should comparing
% it accordingly, and set aside the variables of new arriving/departing flow.

% x is a local solution to the problem when exitflag is positive.
this.interpretExitflag(exitflag, output.message);
options.Action = action;    % This might be used when check feasible solution.
options.ConstraintTolerance = fmincon_opt.ConstraintTolerance;
assert(this.checkFeasible(x,options), 'error: infeasible solution.');

%%%
% The post processing like <optimalFlowRate> is not needed, since the
% objective function (reconfiguration cost) will force those variables to be zero.
this.convert(x, 0);
this.flow_rate = this.getFlowRate(this.temp_vars.x);
this.postProcessing();
this.setPathBandwidth;
this.FlowTable.Rate = this.getFlowRate;
this.Links.Load = this.getLinkLoad;
this.ServiceNodes.Load = this.getNodeLoad;
if nargout >= 1
    cost = this.getCost(options.PricingPolicy, 'const');
    rc_linear = this.get_reconfig_cost('linear', true);
    profit = -fval - cost + rc_linear;
end
end