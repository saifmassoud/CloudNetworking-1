global DEBUG g_results event_num; 
event_num = 0;
g_results = struct;
DEBUG = true;

%% TODO
% 3. test Remove of ListArray/PriorityQueue, nargout.

%% Create Network
if ~isfield(options, 'NetworkType')
    warning('Network type is not provided, use the ''DynamicCloudAccessNetwork'' class.');
    options.NetworkType = 'DynamicCloudAccessNetwork';
end
PN = instantiateclass(options.NetworkType, node_opt, link_opt, VNF_opt, options);
% otherwise
%     error('NetworkSlicing:UnsupportedNetwork', ...
%         'error: %s is not supported for fast reconfiguration', options.NetworkType)
PN.slice_template = Slice.loadSliceTemplate(type.Index);

%% Create Event Dispatcher
% Add the Entity Builder to gernerate random event, which trigers the creation and removal
% of slices.
% Slice Flow Event Dispatcher (SFED)
% NOTE: MAY inorporate the event dispatcher into the network class.
entity_source = ListArray('EntityBuilder');
% for i = 1:3
%     slice_opt = PN.slice_template(i);
%     slice_opt.RandomSeed = seed_dynamic;
%     seed_dynamic = seed_dynamic + 1;
%     entity_source.Add(SliceEntityBuilder(slice_opt));
% end
SFED = SliceFlowEventDispatcher(entity_source, 2017, 0);
% SFED.AddEntityBuilder(SliceEntityBuilder(slice_opt));

%% Event handling
% Event dispatcher's listeners
SFED.AddListener(PN, {'SliceArrive', 'SliceDepart', 'FlowArrive', 'FlowDepart'}, ...
    @PN.eventhandler);
% Network's listeners
% There will be slices listen to the network, after they are added to the network.
PN.AddListener(SFED, {'AddSliceSucceed', 'AddSliceFailed', 'RemoveSliceSucceed', ...
    'RemoveSliceFailed', 'AddFlowSucceed', 'AddFlowFailed', 'RemoveFlowSucceed', ...
    'RemoveFlowFailed'}, @SFED.eventhandler);

%% Add Permanent Slices
% Permanent Slice Entity Builder
num_perm_type = length(type.Permanent);
for t = 1:num_perm_type
    slice_opt = PN.slice_template(type.Permanent(t));
    slice_opt.RandomSeed = seed_dynamic;        % |seed_dynamic| is provided in the configuration script.
    slice_opt.DuplicateFlow = true;
    seed_dynamic = seed_dynamic + 1;
    PSEB = SliceEntityBuilder(slice_opt);
    for s = 1:1%type.PermanentCount(t)
        SFED.AddEntity(PSEB.Build(SFED.CurrentTime, []));
    end
end

%% Main loop
iter_num = 0;
while iter_num < NUM_EVENT
    ev = SFED.nextEvent;
    %%%
    % *output*
    iter_num = iter_num + 1;
    total_iter_num = total_iter_num + 1;
    waitbar(total_iter_num/TOTAL_NUM, progress_bar, ...
            sprintf('Simulation Progress: %d/%d', total_iter_num, TOTAL_NUM));
end