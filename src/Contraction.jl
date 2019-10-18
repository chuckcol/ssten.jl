#=------------------------------------------------------------------------------
						           Contraction
------------------------------------------------------------------------------=#

"""-----------------------------------------------------------------------------
    contract_edge(e,x,k)

This function takes in an edge of a super symmetric tensor and computes the
resulting edges which result from contracting the the edge along k modes with
the vector x.

Input:
------
* e -(Tuple(Array{Int,1},Float)):

    A list of indices paired with an edge value. Note that the list of indices
    corresponds to multiple sets of indices because we consider all.
    permutations.
* x -(Array{Float,1})

    The vector to contract with.
* k - (Int):

    A positive integer which corresponds to the number of modes to contract
    along, must be greater than 0, and less than or equal to the cardinality
    of the edge.

Output:
-------
* condensed_dict - (Dict{Array{Int,1},Number}

    The hyper edges in the lower order tensor which are formed by contracting
    the vector along the hyperedge e.
-----------------------------------------------------------------------------"""
function contract_edge(e::Tuple{Array{Int,1},M},x::Array{N,1},k::Int) where {N <: Number, M<:Number}
    order = length(e)

    (indices,val) = e
    condensed_dict = Dict{Array{Int,1},N}()
    visited_sub_indices = Dict{Array{Int,1},Dict{Array{Int,1},N}}()

    for i in 1:length(indices)
        sub_edge = deleteat!(copy(indices),i)
        if !haskey(visited_sub_indices,sub_edge)
            if k == 1
                condensed_dict[sub_edge] = val*x[indices[i]]
            else
                visited_sub_indices[sub_edge] = contract_edge((sub_edge,val*x[indices[i]]),x,k-1)
            end
        end
    end

    if k != 1
        for (_,sub_dict) in visited_sub_indices
            reduce_dictionaries!(condensed_dict,sub_dict)
        end
    end

    return condensed_dict
end

"""-----------------------------------------------------------------------------
    contract_edge_k_1(e,x)

  This function takes in an edge of a super symmetric tensor and computes the
resulting edges which result from contracting the the edge along k-1 modes with
the vector x, where k is the order of the hyper edge.

Input:
------
* e -(Tuple(Array{Int,1},Number)):

    a list of sorted indices paired with an edge value. Note that the list of
    indices corresponds to multiple sets of indices because we consider all
    permutations.
* x -(Array{Number,1})

    The vector of the same dimenionality of the tensor, to contract with.

Output:
-------
* contraction_vals - (Array{Tuple{Array{Int,1},Number}})

    The hyper edges in the lower order tensor which are formed by contracting
    the vector along the hyperedge e.
-----------------------------------------------------------------------------"""
function contract_edge_k_1(e::Tuple{Array{Int,1},N},x::Array{N,1}) where N <: Number
    (indices,val) = e
    order = length(indices)

    visited_sub_indices = Set{Array{Int,1}}()
    contraction_vals = Array{Tuple{Array{Int,1},N}}(undef,0)

    for i in 1:order
        sub_edge = deleteat!(copy(indices),i)
        if !in(sub_edge,visited_sub_indices)#haskey(scaling_factors,sub_edge)
            scaling = multiplicity_factor(sub_edge)
            push!(visited_sub_indices,sub_edge)
            push!(contraction_vals,([indices[i]],scaling*val*prod(x[sub_edge])))
        end
    end
    return contraction_vals
end

"""-----------------------------------------------------------------------------
    contract(A,x,m)

  This function contracts the tensor along m modes. Note that when the tensor is
dense this function uses Base.Cartesian, and thus in order to generate the loops
with a variable used a trick which instantiates empty arrays of length 0, and
passes them to another function which can pull the orders out to generate the
loops.

Input:
------
* A -(SSSTensor or Array{Number,k}):

    The tensor to contract.
* x - (Array{Number,1}):

    A vector of numbers to contract with.
* m - (Int)

    The number of modes to contract A with x along.

Output:
-------
* y - (SSSTensor or CSC Matrix or Array{Float64,k-m}):

    The output vector of Ax^m. THe output will be sparse if the input tensor is
    sparse, and dense otherwise. When the output is second order, and A is
    sparse, then the output will be a sparse matrix.
-----------------------------------------------------------------------------"""
function contract(A::SSSTensor, x::Array{N,1},m::Int) where {N <: Number}
    @assert length(x) == A.cubical_dimension
    k = order(A)
    @assert 0 < m <= k

    new_edges = Dict{Array{Int,1},N}()
    #compute contractions
    for edge in A.edges
        new_e = contract_edge(Tuple(edge),x,m)
        reduce_dictionaries!(new_edges,new_e)
    end

    if k == m
        for (_,v) in new_edges
            return v
        end
    elseif k - m == 1
        y = zeros(length(x))
        for (e,v) in new_edges
            y[e[1]] = v
        end
        return y
    elseif k - m == 2
	  index = 0
	  nnzs = length(new_edges)
	  I = zeros(Int64,2*nnzs)
	  J = zeros(Int64,2*nnzs)
	  V = zeros(N,2*nnzs)

	  for (e,val) in new_edges
	     i,j = e
		 if i == j
		   index += 1
		   I[index] = i
		   J[index] = j
		   V[index] = val
	     else
		   index += 2
 	       I[index-1] = i
		   J[index-1] = j
		   I[index] = j
		   J[index] = i
		   V[index-1] = val
		   V[index] = val
		 end
	  end
	  return sparse(I[1:index],J[1:index],V[1:index],A.cubical_dimension,A.cubical_dimension)
	else
        return SSSTensor(new_edges,A.cubical_dimension)
    end
end

#Dense Case
function contract(A::Array{N,k}, x::Array{M,1},m::Int64) where {M <: Number,N <: Number,k}

    return dense_contract(A,x,zeros(Int,repeat([0],m)...),
	                      zeros(Int,repeat([0],k-m)...))
end

@generated function dense_contract(A::Array{N,k}, x::Array{M,1},
                                   B::Array{Int,m}, C::Array{Int,p}) where
								   {M<:Number,N<:Number,k,m,p}
    quote
        n = size(A)[1]
        @assert n == length(x)
        @assert $k >= m

        y = zeros(N,repeat([n],$k - $m)...)

        @nloops $k i A begin
            xs = prod(x[collect(@ntuple $m j-> i_{j+$p})])
            (@nref $p y i) += xs*(@nref $k A i)
        end
	if $k == m
	  for val in y
	    return val
	  end
	else
          return y
        end
      end
end

"""-----------------------------------------------------------------------------
    contract_k_1(A,x)

This function contracts the tensor along k-1 modes to produce a vector. This
will produce the same result as contract(A,x,k-1), but runs in a much faster
time.

Inputs
------
* A -(SSSTensor):

    The tensor to contract.
* x - (Array{Number,1}):

    A vector of numbers to contract with.
Outputs
-------
* y - (Array{Number,1}):

    The output vector of Ax^{k-1}.
-----------------------------------------------------------------------------"""
function contract_k_1(A::SSSTensor, x::Array{N,1}) where {N <: Number}
    @assert length(x) == A.cubical_dimension

    new_edges = Array{Tuple{Array{Int,1},N}}(undef,0)
    y = zeros(A.cubical_dimension)

    #compute contractions
    for edge in A.edges
        contracted_edges = contract_edge_k_1(Tuple(edge),x)
        push!(new_edges,contracted_edges...)
    end
    #reduce edges and copy into new vector
    edge_dict = reduce_edges(new_edges)

    for (i,v) in edge_dict
        y[i[1]] = v
    end
    return y
end

"""-----------------------------------------------------------------------------
    contract_multi(A,vs)

  This function computes the result of contracting the tensor A by the columns
of the array Vs.

-----------------------------------------------------------------------------"""
function contract_multi(A::SSSTensor, Vs::Array{N,2}) where N <: Number
  k = order(A)
  n,m = size(Vs)
  @assert m <= k
  @assert n == A.cubical_dimension

  i = 1
  while true
    if k - i >= 2
      global A_sub = contract(A,Vs[:,i],1)
    elseif k - i == 1
	  global A_sub = A_sub*Vs[:,i]
    elseif k - i == 0
	  global A_sub = dot(A_sub,Vs[:,i])
    end
	i += 1

	if i > m #no more vectors
	  return A_sub
    end
  end
end

function contract(A::SSSTensor,v::Array{N,1},u::Array{N,1}) where N <: Number
  return contract_multi(A,hcat(v,u))
end
