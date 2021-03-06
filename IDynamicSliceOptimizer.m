classdef (Abstract, HandleCompatible) IDynamicSliceOptimizer	
  properties (Constant)
    GLOBAL_OPTIONS = StaticProperties;
  end

	properties(Constant)
		NUM_MEAN_BETA = 15;
		ENABLE_DYNAMIC_NORMALIZER = true;
		GET_BETA_METHOD = 'Average';    % 'Average', 'ExponetialMovingAverage';
  end 
 
  properties
    % the variable |b_derive_vnf| decide if update VNF instance capacity.
    %    |b_derive_vnf=true|: derive VNF instance capacity from the optimization
    %    results of |Variables.z|;
    %    |b_derive_vnf=false|: apply |Variables.v| as VNF instance capacity.
    % For first time slice dimensioning,
    %   VNF capacity is the sum of VNF instance assigment (sum of z_npf);
    % For later reallocation (FSR2), the VNF capacity should be set as the optimized
    % variables (|this.Variables.v|, which might be larger than sum of |z_npf|, due to
    % reconfiguration cost).
    b_derive_vnf = true;
    b_dim = true;      % reset each time before reconfigurtion.
		vnf_reconfig_cost;
    old_state;
		changed_index;
  end

  properties (Abstract)
    options;        % Options on performing optimizarion.
  end
  
	properties (Access = protected)
		a = 0.8;        % a for the history, should have a larger weight (EMA)
		%% options for slice dimensioning schedule algorithm
		% 'omega_upper':
		% 'omega_lower':
		% 'alpha':
		% 'series_length'
		% 'trend_length'
		sh_options = struct('omega_upper', 0.97, 'omega_lower', 0.85, ...
			'alpha', 0.3, 'series_length', 40, 'trend_length', 20);
		%% data for slice dimensioning schdule algorithm
		% 'omegas':
		% 'profits'
		% 'omega_trend':
		% 'profit_trend':
		sh_data = struct('omegas', [] , 'profits', [], ...
			'omega_trend', struct('ascend', [], 'descend', []),...
			'profit_trend', struct('ascend', [], 'descend', []),...
			'index', 0, 'reserve_dev', 0);
		invoke_method = 0;
		old_variables;      % last one configuration, last time's VNF instance capcity is the |v| field;
		lower_bounds = struct([]);
		upper_bounds = struct([]);
		topts;              % used in optimization, avoid passing extra arguments.
		max_flow_rate;
		init_gamma_k;
		init_q_k;
		diff_state;         % reset each time before reconfiguration.

    raw_beta;
		raw_cost;
		raw_costv;
  end

  methods (Abstract)
    [exitflag,fidx] = executeMethod(this, action);
    s = save_state(this);
    restore_state(this);
  end
  
  methods (Abstract, Access = protected)
    b = getbeta(this);
    [profit, cost] = handle_zero_flow(this, new_opts);
    identify_change(this, ~)
    [total_cost, reconfig_cost] = get_reconfig_cost(this, model, isfinal);
		update_reconfig_costinfo(this, action, bDim);
  end
  
  methods
    function this = IDynamicSliceOptimizer(slice, slice_data)
      % Interval for performing dimensioning should be configurable.
      this.options = structmerge(this.options, ...
        getstructfields(slice_data, ...
        {'TimeInterval', 'EventInterval', 'Trigger'}, 'ignore'));
      this.options = structmerge(this.options, ...
        getstructfields(slice_data, 'ReconfigMethod' , 'error'));

      switch this.options.ReconfigMethod
        case {ReconfigMethod.DimconfigReserve, ReconfigMethod.DimconfigReserve0,...
            ReconfigMethod.FastconfigReserve}
          this.options = structmerge(this.options, ...
            getstructfields(slice_data, 'bReserve', 'default', 2));
        case ReconfigMethod.DimBaseline
          this.options = structmerge(this.options, ...
            getstructfields(slice_data, 'bReserve', 'default', 0));
          this.sh_options.omega_upper = 1;
          this.sh_options.omega_lower = 0.9;
        case {ReconfigMethod.Dimconfig,ReconfigMethod.Fastconfig}
          this.options = structmerge(this.options, ...
            getstructfields(slice_data, 'bReserve', 'default', 0));
          this.sh_options.omega_upper = 1;
        otherwise
          this.options = structmerge(this.options, ...
            getstructfields(slice_data, 'bReserve', 'default', 1));
      end
      switch this.options.ReconfigMethod
        case {ReconfigMethod.DimBaseline, ReconfigMethod.Dimconfig}
          u = 0.2;
        case ReconfigMethod.DimconfigReserve0
          u = 0.1;
        otherwise
          u = 0;
      end
      if this.options.ReconfigMethod == ReconfigMethod.DimconfigReserve
        this.sh_options = structmerge(this.sh_options, ...
          getstructfields(slice_data, 'UtilizationVariance', 'default', 0.05));
      else
        this.sh_options.UtilizationVariance = u;
      end
      if this.options.bReserve
        if this.options.ReconfigMethod == ReconfigMethod.DimconfigReserve0
          this.options.Reserve = 0;
        else
          this.options = structmerge(this.options, ...
            getstructfields(slice_data, 'Reserve','default', 0.9));
        end
      end
      
      if isfield(this.options, 'EventInterval')
        slice.time.DimensionInterval = this.options.EventInterval/(2*slice.FlowArrivalRate); % both arrival and departure events
        slice.time.MinDimensionInterval = 1/5*slice.time.DimensionInterval;
      elseif isfield(this.options, 'TimeInterval')
        slice.time.DimensionInterval = slice.options.TimeInterval;
      elseif isfield(this.options, 'Trigger')
        slice.time.DimensionInterval = 10/slice.FlowArrivalRate;
      end
      slice.time.DimensionIntervalModified = slice.time.DimensionInterval;
      if ~IDynamicSliceOptimizer.ENABLE_DYNAMIC_NORMALIZER
        if ~isfield(slice_data, 'ReconfigScaler')
          this.options.ReconfigScaler = 1;
        else
          this.options.ReconfigScaler = slice_data.ReconfigScaler;
        end
      end
      
      if isfield(slice_data, 'penalty')
        this.options.penalty = slice_data.penalty;
      end
    end
  
  end
  
  methods
    function update_options(this, options)
      if isfield(options, 'ResidualCapacity')
        this.options.ResidualCapacity = options.ResidualCapacity;
      end
    end

    [profit,cost] = fastReconfigure(this, action, options);
    [profit,cost, exitflag, fidx] = DimensioningReconfigure( this, action, new_opts );
  end
end