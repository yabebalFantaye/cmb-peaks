! $Id$
! Synthesize a rank-ordered weigth masks for calculating L-moments
! invoke: lmask <map.fits[:channel]> <lmask.fits[:moments]> [mask.fits[:channel]] [lmap-base]

program lmask

! HEALPix includes
use mapio
use extension

implicit none


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

integer :: datach = 1, maskch = 1, nmoms = 4		! defaults
integer :: i, n, npix, nused, nside = 0, ord = 0	! map format

character(len=80) :: fin, fout, fmask
real(IO), allocatable :: Map(:), Mask(:), Mout(:,:)
integer,  allocatable :: indx(:), rank(:)
real(DP), allocatable :: M(:), P(:,:)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! input map (and optional signal channel selection)
! output map (and optional number of moments selection)
call getArgument(1, fin ); call parse(fin, datach)
call getArgument(2, fout); call parse(fout, nmoms)

! read input map
call read_channel(fin, Map, nside, datach, ord)
npix = nside2npix(nside); n = npix-1

! allocate dynamic arrays to store output maps and ranks
allocate(Mout(0:n,nmoms), P(nmoms,nmoms))
allocate(M(npix), indx(npix), rank(npix)); M = Map

! read mask if specified
if (nArguments() < 3) then
	allocate(Mask, mold=Map); Mask = 1.0
else
	call getArgument(3, fmask); call parse(fmask, maskch)
	call read_channel(fmask, Mask, nside, maskch, ord)
end if

! masked pixels are not ranked
where (isnan(Map)) Mask = 0.0
where (Mask == 0.0) M = HUGE(M)
nused = count(Mask /= 0.0)

! compute rank ordering and L-weights
call gegenbauer(P, nmoms-1, 1.0)
call indexx(npix, M, indx)
call rankx(npix, indx, rank)

forall (i=0:n) Mout(i,:) = Mask(i) * matmul(P, X(rank(i+1), nused, nmoms-1))

! output L-weight masks (to a single FITS container)
call write_map(fout, Mout, nside, ord, creator='LMASK')

! output L-weighted maps (to separate FITS files) if requested
if (nArguments() > 3) then
	call getArgument(4, fout)
	
	forall (i=0:n) Mout(i,:) = Map(i) * Mout(i,:)
	
	do i = 1,nmoms
		write (fmask,'(A,A1,I1,A5)') trim(fout), '-', i, '.fits'
		call write_map(fmask, Mout(:,(/i/)), nside, ord, creator='LMASK')
	end do
end if


contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! scaled Gegenbauer polynomials P(k,alpha,x) = C(k,alpha/2,x)/C(k,alpha/2,1)
! generalize Legendre P (alpha=1), Chebyshev T (alpha=0) and Chebyshev U (alpha=2)
! satisfy P(0) = 1.0; P(1) = x; P(k+1) = ((2*k+alpha)*x*P(k) - k*P(k-1))/(k+alpha)
! returns *shifted* polynomial coefficients as P(k,alpha,2*x-1) = sum(P(k,n)*x^n)
subroutine gegenbauer(P, l, alpha)
	integer k, l; real P(0:l,0:l), alpha
	
	P = 0.0; P(0,0) = 1.0; P(1,1) = 2.0; P(1,0) = -1.0; do k = 1,l-1
		P(k+1,:) = ((2*k+alpha)*(2.0*cshift(P(k,:),-1)-P(k,:)) - k*P(k-1,:))/(k+alpha)
	end do
end subroutine gegenbauer

! Calculate L-weights from rank order vector X using matmul(P,X)
pure function X(r,n,l)
	integer, intent(in) :: r, n, l; integer k; real X(0:l)
	
	X(0) = 1.0; do k = 1,l; X(k) = X(k-1) * (r-k)/(n-k); end do
end function X


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! parse optional channel specification
subroutine parse(file, channel)
	character(*) file
	integer channel, i
	
	i = index(file, ":", .true.)
	
	if (i > 0) then
		read (file(i+1:),*) channel
		file(i:) = ""
	end if
end subroutine parse

! read a single map channel, allocating storage if necessary
subroutine read_channel(fin, M, nside, channel, ord)
	character(*) fin
	real(IO), allocatable :: M(:), TMP(:,:)
	integer channel, nside, npix, nmaps, ord
	
	! read full map into temporary storage
	nmaps = 0; call read_map(fin, TMP, nside, nmaps, ord)
	if (channel > nmaps) call abort(trim(fin) // ": too few channels in an input map")
	
	! allocate storage if needed
	npix = nside2npix(nside); if (.not. allocated(M)) allocate(M(0:npix-1))
	if (size(M) /= npix) call abort(trim(fin) // ": unexpected storage array shape")
	
	! copy over the data we want, free the full map
	M = TMP(:,channel); deallocate(TMP)
end subroutine read_channel

end
