function engine = cbk_inf_engine(bnet, varargin)
% Just the same as bk_inf_engine, but you can specify overlapping clusters.

ss = length(bnet.intra);
% set default params
clusters = 'exact';

if nargin >= 2
  args = varargin;
  nargs = length(args);
  for i=1:2:nargs
    switch args{i},
     case 'clusters',  clusters = args{i+1};
     otherwise, error(['unrecognized argument ' args{i}])
    end
  end
end

if strcmp(clusters, 'exact')
  %clusters = { compute_interface_nodes(bnet.intra, bnet.inter) };
  clusters = { 1:ss };
elseif strcmp(clusters, 'ff')
  clusters = num2cell(1:ss);
end


% We need to insert the prior on the clusters in slice 1,
% and extract the posterior on the clusters in slice 2.
% We don't need to care about the separators, b/c they're subsets of the clusters.
C = length(clusters);
clusters2 = cell(1,2*C);
clusters2(1:C) = clusters;
for c=1:C
  clusters2{c+C} = clusters{c} + ss;
end

onodes = bnet.observed;
obs_nodes = [onodes(:) onodes(:)+ss];
engine.sub_engine = jtree_inf_engine(bnet, 'clusters', clusters2);

%FH >>>
%Compute separators. 
ns = bnet.node_sizes(:,1);
ns(onodes) = 1;
[clusters, separators] = build_jt(clusters, 1:length(ns), ns);
S = length(separators);
engine.separators = separators;

%Compute size of clusters.
cl_sizes = zeros(1,C);
for c=1:C
    cl_sizes(c) = prod(ns(clusters{c}));
end

%Assign separators to the smallest cluster subsuming them.
engine.cluster_ass_to_separator = zeros(S, 1);
for s=1:S
    subsuming_clusters = [];
    %find smallest cluster containing s
    for c=1:C
        if mysubset(separators{s}, clusters{c}) 
            subsuming_clusters(end+1) = c;
        end
    end
    c = argmin(cl_sizes(subsuming_clusters));
    engine.cluster_ass_to_separator(s) = subsuming_clusters(c);
end

%<<< FH

engine.clq_ass_to_cluster = zeros(C, 2);
for c=1:C
  engine.clq_ass_to_cluster(c,1) = clq_containing_nodes(engine.sub_engine, clusters{c});
  engine.clq_ass_to_cluster(c,2) = clq_containing_nodes(engine.sub_engine, clusters{c}+ss);
end
engine.clusters = clusters;

engine.clq_ass_to_node = zeros(ss, 2);
for i=1:ss
  engine.clq_ass_to_node(i, 1) = clq_containing_nodes(engine.sub_engine, i);
  engine.clq_ass_to_node(i, 2) = clq_containing_nodes(engine.sub_engine, i+ss);
end



% Also create an engine just for slice 1
bnet1 = mk_bnet(bnet.intra1, bnet.node_sizes_slice, 'discrete', myintersect(bnet.dnodes, 1:ss), ...
		'equiv_class', bnet.equiv_class(:,1), 'observed', onodes);
for i=1:max(bnet1.equiv_class)
  bnet1.CPD{i} = bnet.CPD{i};
end

engine.sub_engine1 = jtree_inf_engine(bnet1, 'clusters', clusters);

engine.clq_ass_to_cluster1 = zeros(1,C);
for c=1:C
  engine.clq_ass_to_cluster1(c) = clq_containing_nodes(engine.sub_engine1, clusters{c});
end

engine.clq_ass_to_node1 = zeros(1, ss);
for i=1:ss
  engine.clq_ass_to_node1(i) = clq_containing_nodes(engine.sub_engine1, i);
end

engine.clpot = []; % this is where we store the results between enter_evidence and marginal_nodes
engine.filter = [];
engine.maximize = [];
engine.T = [];

engine.bel = [];
engine.bel_clpot = [];
engine.slice1 = [];
%engine.pot_type = 'cg';
% hack for online inference so we can cope with hidden Gaussians and discrete
% it will not affect the pot type used in enter_evidence
engine.pot_type = determine_pot_type(bnet, onodes);

engine = class(engine, 'cbk_inf_engine', inf_engine(bnet));




function [cliques, seps, jt_size] = build_jt(cliques, vars, ns)
% BUILD_JT connects the cliques into a jtree, computes the respective 
% separators and the size of the resulting jtree.
%
% [cliques, seps, jt_size] = build_jt(cliques, vars, ns)
% ns(i) has to hold the size of vars(i)
% vars has to be a superset of the union of cliques.

%======== Compute the jtree with tool from BNT. This wants the vars to be 1:N.
%==== Map from nodes to their indices.
%disp('Computing jtree for cliques with vars and ns:');
%cliques
%vars
%ns'

inv_nodes = sparse(1,max(vars));
N = length(vars);
for i=1:N
    inv_nodes(vars(i)) = i;
end

tmp_cliques = cell(1,length(cliques));
%==== Temporarily map clique vars to their indices.
for i=1:length(cliques)
    tmp_cliques{i} = inv_nodes(cliques{i});
end

%=== Compute the jtree, using BNT.
[jtree, root, B, w] = cliques_to_jtree(tmp_cliques, ns);


%======== Now, compute the separators between connected cliques and their weights.
seps = {};
s_w = [];
[is,js] = find(jtree > 0);
for k=1:length(is)
  i = is(k); j = js(k);
  sep = vars(find(B(i,:) & B(j,:))); % intersect(cliques{i}, cliques{j});
  if i>j | length(sep) == 0, continue; end;
  seps{end+1} = sep;
  s_w(end+1) = prod(ns(inv_nodes(seps{end})));
end

cl_w = sum(w);
sep_w = sum(s_w);
assert(cl_w > sep_w, 'Weight of cliques must be bigger than weight of separators');

jt_size = cl_w + sep_w;
% jt.cliques = cliques;
% jt.seps = seps;
% jt.size = jt_size;
% jt.ns = ns';
% jt;