# Test for history and matchreplace
isunless(x::Expr) = x.head == :gotoifnot
isunless(x) = false
islabelnode(x::LabelNode) = true
islabelnode(x) = false
isgoto(x::GotoNode) = true
isgoto(x) = false

function is_unless_label(label, hist, histpos = 1)
    islabelnode(label) || return false
    unless = hist[histpos][1]
    unless_label = unless.args[2]
    unless_label == label.label
end
function is_goto_label(label, hist, histpos)
    islabelnode(label) || return false
    goto = hist[histpos][1]
    goto.label == label.label
end
function is_goto(goto, hist, histpos)
    isgoto(goto) || return false
    label = hist[histpos][1]
    goto.label == label.label
end


ifelse_pattern = (
    isunless, # if branch
    anything, # if body
    isgoto, # goto to jump over else
    (l, h)-> is_unless_label(l, h, 1),
    anything,   # else body
    (l, h)-> is_goto_label(l, h, 3) # label matching above goto
)
while_pattern = (
    islabelnode, # loop goto label
    isunless, # while condition branch
    anything, # body
    Greed(islabelnode, 0:1), # optional continue label
    (l,h)-> is_goto(l, h, 1), # goto label, matching first label
    (l,h)-> is_unless_label(l, h, 2) # goto and break
)

if_pattern = (isunless, anything, is_unless_label)
function test{T}(a, b::T)
    if a == 10
        x = if b == 22
            7
        else
            8
        end
        for i=1:100
            x += i
            x -= 77
            if i == 77
                continue
            elseif i == 99
                break
            end
        end
        return x
    else
        return 77
    end
end

if VERSION < v"0.6.0-dev"
    function get_ast(f, types)
        Base.uncompressed_ast(code_lowered(f, types)[])
    end
else
    function get_ast(f, types)
        li = code_lowered(test, types)[]
        ast = li.code
        if isa(ast, Vector{UInt8})
            return Base.uncompressed_ast(li)
        end
        ast
    end
end
ast = get_ast(test, (Int, Int))
filter!(x-> x != nothing && !isa(x, LineNumberNode), ast)

matches = matchitall(ast, while_pattern)
@test length(matches) == 1
@test vcat(matches[1]...) == ast[12:27]

matches = matchitall(ast, ifelse_pattern)
@test length(matches) == 3
@test vcat(matches[1]...) == ast[3:8]
@test vcat(matches[2]...) == ast[19:25]
@test vcat(matches[3]...) == ast[23:27]


ast = matchreplace(ast, while_pattern) do loop_label, unless, whilebody, continue_label, goto, break_label
    condition = unless[1].args[1]
    whilebody = collect(whilebody)
    block = Expr(:block, whilebody...)
    Expr(:while, condition, block)
end

ast = matchreplace(ast, ifelse_pattern) do unless, ifbody, _1, _2, elsebody, _3
    condition = unless[1].args[1]
    ifbody = Expr(:block, ifbody...)
    elsebody = Expr(:block, elsebody...)
    Expr(:if, condition, ifbody, elsebody)
end

matches = matchitall(ast, if_pattern)
@test length(matches) == 1
@test vcat(matches[1]...) == ast[2:9]
