function tf = executeMethod(this, action)
global g_results event_num DEBUG; %#ok<NUSED>
options = getstructfields(this.Parent.options, {'Method', 'Form'});  % Form = {'compact'|'normal'}
this.getAs_res;         % TODO, incremental upate of As_res.
% |edge_reconfig_cost| is a vector, and we know edge-path incident matrix, so
% we can calculate the |x_reconfig_cost| for all paths.
this.x_reconfig_cost = (this.I_edge_path)' * this.VirtualLinks.ReconfigCost;
this.z_reconfig_cost = repmat(this.VirtualDataCenters.ReconfigCost, ...
    this.NumberPaths*this.NumberVNFs, 1);
switch options.Method
    case 'reconfig'
        % provide 'method' and 'model' to customize the <optimalFlowRate>
        % Since we adopt |FixedCost| model, the resource cost that is a
        % constant, is not include in the objective value |profit|. So, we
        % should exclude it from the |profit|, as well as the reconfiguration
        % cost.
        options.CostModel = 'fixcost';
        profit = this.optimalFlowRate(options);
        %%
        % After reconfiguration VNF instance capcity has changed.
        this.VNFCapacity = this.getVNFInstanceCapacity;
        g_results.Profit(event_num,1) = ...
            profit - this.getSliceCost('quadratic-price', 'const');
        g_results.Solution(event_num,1) = this.Variables;
        [   g_results.Cost(event_num,1), ...
            g_results.NumberReconfig(event_num,1),...
            g_results.RatioReconfig(event_num,1),...
            g_results.NumberVariables(event_num,1)] ...
            = this.get_reconfig_cost('const');
        %% Save the VNF capacity to the previous state.
        this.prev_vnf_capacity = this.VNFCapacity;
    case 'fastconfig'
        profit = this.fastReconfigure(action, options);
        % Reconfiguration cost has been counted in |profit|, while resource
        % cost is not. So we need to exlude only part of the resource cost
        % from the profit.
        g_results.Solution(event_num,1) = this.Variables;
        [   g_results.Cost(event_num,1),...
            g_results.NumberReconfig(event_num,1),...
            g_results.RatioReconfig(event_num,1),...
            g_results.NumberVariables(event_num,1)]...
            = this.get_reconfig_cost('const');
        g_results.Profit(event_num,1) = ...
            profit - g_results.Cost(event_num,1) + ...
            this.get_reconfig_cost('linear') - ...
            this.getSliceCost('quadratic-price', 'none');
    case 'fastconfig2'
        profit = this.fastReconfigure2(action, options);
        this.VNFCapacity = this.getVNFInstanceCapacity;
        g_results.Solution(event_num,1) = this.Variables;
        [   g_results.Cost(event_num,1),...
            g_results.NumberReconfig(event_num,1),...
            g_results.RatioReconfig(event_num,1),...
            g_results.NumberVariables(event_num,1)]...
            = this.get_reconfig_cost('const');
        g_results.Profit(event_num,1) = ...
            profit - g_results.Cost(event_num,1) + ...
            this.get_reconfig_cost('linear') - ...
            this.getSliceCost('quadratic-price', 'none');
        this.prev_vnf_capacity = this.VNFCapacity;
    case {'dimconfig', 'dimconfig2'}
        if mod(this.num_received_events, this.interval_events) == 1
            profit = this.DimensioningReconfigure(action, options);
            this.VNFCapacity = this.getVNFInstanceCapacity;
        elseif strcmpi('dimconfig', options.Method)
            profit = this.fastReconfigure(action, options);
        else
            profit = this.fastReconfigure2(action, options);
            this.VNFCapacity = this.getVNFInstanceCapacity;
        end
        g_results.Solution(event_num,1) = this.Variables;
        [   g_results.Cost(event_num,1),...
            g_results.NumberReconfig(event_num,1),...
            g_results.RatioReconfig(event_num,1),...
            g_results.NumberVariables(event_num,1)]...
            = this.get_reconfig_cost('const');
        g_results.Profit(event_num,1) = ...
            profit - g_results.Cost(event_num,1) + ...
            this.get_reconfig_cost('linear') - ...
            this.getSliceCost('quadratic-price', 'none');
        this.prev_vnf_capacity = this.VNFCapacity;
    otherwise
        error('NetworkSlicing:UnsupportedMethod', ...
            'error: unsupported method (%s) for network slicing.', ...
            options.Method) ;
end
g_results.NumberFlows(event_num,1) = this.NumberFlows;
tf = true;
end