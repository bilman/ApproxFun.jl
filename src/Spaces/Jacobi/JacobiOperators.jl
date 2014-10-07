## Evaluation

function Base.getindex(op::Evaluation{JacobiSpace,Bool},kr::Range)
    @assert op.order <= 2
    sp=op.space
    a=sp.a;b=sp.b
    x=op.x
    
    if op.order == 0
        jacobip(kr-1,a,b,x?1.0:-1.0)
    elseif op.order == 1&& !x && b==0 
        d=domain(op)
        @assert isa(d,Interval)
        Float64[tocanonicalD(d,d.a)*.5*(a+k)*(k-1)*(-1)^k for k=kr]
    elseif op.order == 1
        d=domain(op)
        @assert isa(d,Interval)
        if kr[1]==1
            0.5*tocanonicalD(d,d.a)*(a+b+kr).*[0.,jacobip(0:kr[end]-2,1+a,1+b,x?1.:-1.)]
        else
            0.5*tocanonicalD(d,d.a)*(a+b+kr).*jacobip(kr-1,1+a,1+b,x?1.:-1.)
        end
    elseif op.order == 2
        @assert !x && b==0     
        @assert domain(op)==Interval()        
        Float64[-.125*(a+k)*(a+k+1)*(k-2)*(k-1)*(-1)^k for k=kr]
    end
end
function Base.getindex(op::Evaluation{JacobiSpace,Float64},kr::Range)
    @assert op.order == 0
    jacobip(kr-1,op.space.a,op.space.b,tocanonical(domain(op),op.x))        
end

## Multiplication

function addentries!(M::Multiplication{ChebyshevSpace,JacobiSpace},A::ShiftArray,kr::Range1)
    for k=kr
        A[k,0]=M.f.coefficients[1] 
    end
    
    if length(M.f) > 1
        sp=M.space
        jkr=max(1,kr[1]-length(M.f)+1):kr[end]+length(M.f)-1
        ##TODO: simplify shift array and combine with Ultraspherical
        J=BandedArray(ShiftArray(zeros(length(jkr),3),1-jkr[1],2),jkr)
        addentries!(JacobiRecurrenceOperator(sp.a,sp.b).',J.data,jkr)  #Multiplication is transpose
    
        C1=J
    
        shiftarray_const_addentries!(C1.data,M.f.coefficients[2],A,kr)

        C0=BandedArray(ShiftArray(ones(length(jkr),1),1-jkr[1],1),jkr)
    
        for k=1:length(M.f)-2    
            C1,C0=2J*C1-C0,C1
            shiftarray_const_addentries!(C1.data,M.f.coefficients[k+2],A,kr)    
        end
    end
    
    A
end


## Derivative

Derivative(J::JacobiSpace,k::Integer)=k==1?Derivative{JacobiSpace,Float64}(J,1):TimesOperator(Derivative(JacobiSpace(J.a+1,J.b+1,J.domain),k-1),Derivative{JacobiSpace,Float64}(J,1))

rangespace(D::Derivative{JacobiSpace})=JacobiSpace(D.space.a+D.order,D.space.b+D.order,domain(D))
bandinds(D::Derivative{JacobiSpace})=0,D.order
bandinds(D::Integral{JacobiSpace})=-D.order,0   



function addentries!(T::Derivative{JacobiSpace},A::ShiftArray,kr::Range)
    d=domain(T)
    for k=kr
        A[k,1]+=(k+1+T.space.a+T.space.b)./length(d)
    end
    A
end


## Integral

## Conversion
# We can only increment by a or b by one, so the following
# multiplies conversion operators to handle otherwise

function Conversion(L::JacobiSpace,M::JacobiSpace)
    @assert (isapprox(M.b,L.b)||M.b>=L.b) && (isapprox(M.a,L.a)||M.a>=L.a)
    dm=domain(M)
    if isapprox(M.a,L.a) && isapprox(M.b,L.b)
        SpaceOperator(IdentityOperator(),L,M)
    elseif (isapprox(M.b,L.b+1) && isapprox(M.a,L.a)) || (isapprox(M.b,L.b) && isapprox(M.a,L.a+1))
        Conversion{JacobiSpace,JacobiSpace,Float64}(L,M)
    elseif M.b > L.b+1
        Conversion(JacobiSpace(M.a,M.b-1,dm),M)*Conversion(L,JacobiSpace(M.a,M.b-1,dm))    
    else  #if M.a >= L.a+1
        Conversion(JacobiSpace(M.a-1,M.b,dm),M)*Conversion(L,JacobiSpace(M.a-1,M.b,dm))            
    end
end   

bandinds(C::Conversion{JacobiSpace,JacobiSpace})=(0,1)



function getdiagonalentry(C::Conversion{JacobiSpace,JacobiSpace},k,j)
    L=C.domainspace
    if L.b+1==C.rangespace.b
        if j==0
            k==1?1.:(L.a+L.b+k)/(L.a+L.b+2k-1)
        else
            (L.a+k)./(L.a+L.b+2k+1)
        end    
    elseif L.a+1==C.rangespace.a
        if j==0
            k==1?1.:(L.a+L.b+k)/(L.a+L.b+2k-1)
        else
            -(L.b+k)./(L.a+L.b+2k+1)
        end  
    else
        error("Not implemented")  
    end
end




# return the space that has banded Conversion to the other
function conversion_rule(A::JacobiSpace,B::JacobiSpace)
    if A.a<=B.a || A.b<=B.b
        A
    else
        B
    end
end



## Ultraspherical Conversion

# Assume m is compatible
bandinds{m}(C::Conversion{UltrasphericalSpace{m},JacobiSpace})=0,0


function addentries!(C::Conversion{ChebyshevSpace,JacobiSpace},A::ShiftArray,kr::Range)
    S=rangespace(C)
    @assert S.a==S.b==-0.5
    jp=jacobip(0:kr[end],-0.5,-0.5,1.0)
    for k=kr
        A[k,0]+=1./jp[k]
    end
    
    A
end

function addentries!(C::Conversion{JacobiSpace,ChebyshevSpace},A::ShiftArray,kr::Range)
    S=domainspace(C)
    @assert S.a==S.b==0.

    jp=jacobip(0:kr[end],-0.5,-0.5,1.0)
    for k=kr
        A[k,0]+=jp[k]
    end
    
    A
end

function getdiagonalentry{m}(C::Conversion{UltrasphericalSpace{m},JacobiSpace})
    @assert B.a+.5==m&&B.b+.5==m
    gamma(2m+k)*gamma(m+0.5)/(gamma(2m)*gamma(m+k+0.5))
end

function getdiagonalentry{m}(C::Conversion{JacobiSpace,UltrasphericalSpace{m}})
    @assert B.a+.5==m&&B.b+.5==m
    (gamma(2m)*gamma(m+k+0.5))/(gamma(2m+k)*gamma(m+0.5))
end


function conversion_rule{m}(A::UltrasphericalSpace{m},B::JacobiSpace)
    if B.a+.5==m&&B.b+.5==m
        A
    else
        NoSpace()
    end
end


