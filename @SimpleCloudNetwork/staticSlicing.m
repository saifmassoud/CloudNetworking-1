%% Static Network Slicing
% In the static slicing method, once the resource is allocated to a slice,
% the allocation scheme is not changed during its lifetime.
%
% *NOTE*: when link and node resources are exhausted, some slice request
% might be rejected.
%%
% |options|: 
%		*SlicingMethod*: _StaticPricing_
%
% *TODO*: we can adjust the unit price according to the residual capacity.
function output = staticSlicing(this, slice)
options = getstructfields(this.options, ...
	{'ConstraintTolerance','SlicingMethod','Form'}, 'ignore');
if options.SlicingMethod.IsPricing  % options for _optimalFlowRate_.
    options.PricingPolicy = 'linear';
end

if nargin>=2 && ~isempty(slice)
    %% Allocate Resource to the new arrival slice
    % The residual capacity of the substrate network is available to the slice.
    slice.Links.Price = this.readLink('Price',slice.Links.PhysicalLink);
    slice.ServiceNodes.Price = this.readDataCenter('Price',slice.getDCPI);
    % ss = slice.copy;
    slice.ServiceNodes.Capacity = this.readDataCenter('ResidualCapacity', slice.getDCPI);
		slice.Links.Capacity = ...
			this.readLink('ResidualCapacity', slice.Links.PhysicalLink);
		slice.Optimizer.setProblem('LinkPrice', slice.Links.Price,...
			'NodePrice', slice.ServiceNodes.Price);
    [~] = slice.Optimizer.optimalFlowRate(options);
    %% Finalize the new slice and the substrate network
    % # After the optimization, the resource allocation variables, flow rate, virtual
    % node/link load of the last slice have been recorded.
    % # Calculate and announce the resource prices to the new slice. The price is fixed in
    % the static slicing method, so the price has been calculated in advance.
    % # Record the substrate network's node/link load, price. When a slice arrive or
    % depart, the network load changes.
    slice.Links.Capacity = slice.Links.Load;
    slice.ServiceNodes.Capacity = slice.ServiceNodes.Load;
    slice.Optimizer.setProblem('Price', []);
end

load = this.getNetworkLoad;
this.writeDataCenter('Load', load.Node);
this.writeLink('Load', load.Link);

% Calculate the output
options.Slices = this.slices;
output = this.calculateOutput([], options);
end
