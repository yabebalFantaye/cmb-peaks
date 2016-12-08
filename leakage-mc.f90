! power leakage matrix calculated using Monte-Carlo
! invoke: leakage-mc mask.fits leakage.fits

program leakage_mc

! HEALPix includes
use mapio
use imageio
use alm_tools
use extension

implicit none


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


character(len=8000) :: file, output
integer :: nmaps = 0, nside = 0, ord = 0
real(DP), dimension(:,:), allocatable :: mask
real(DP), allocatable :: map(:,:), W(:,:,:)
complex(DPC), allocatable :: alms(:,:,:)

integer, parameter :: lcut = 128
integer n, lmax, l1, l2, seed(2)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! parse arguments
if (nArguments() /= 2) call abort("cannot parse command line expression supplied")
call getArgument(1, file); call getArgument(2, output)

! read in mask map
call read_map(file, mask, nside, nmaps, ord); lmax = 3*nside-1; if (lmax > lcut) lmax = lcut
if (nmaps > 1) write (0,*) "warning: only temperature mask Cl's will be used in leakage calculation!"

! convert the order to RING
select case (ord)
        case (RING); continue
        case (NEST); call convert_nest2ring(nside, mask); ord = RING
        case default; call abort("unknown ordering of mask map encountered")
end select

! allocate storage
n = nside2npix(nside)-1
allocate(alms(1:3,0:lmax,0:lmax), map(0:n,3), W(4,0:lmax,0:lmax))

! initialize random number generator (use urandom on clusters!)
open (333, file="/dev/random", action='read', form='binary')
read (333) seed; call random_seed(PUT=seed); close (333)

! compute leakage matrix
!$omp parallel do
do l2 = 0,lmax
	call leakage(W(:,:,l2),l2)
end do

!forall (l1=0:lmax,l2=0:lmax) W(1,l1,l2) = log(W(1,l1,l2)**2/W(1,l1,l1)/W(1,l2,l2))/2.0

call image2fits(output, W, [0.0,real(lmax)], [0.0,real(lmax)], ['K','K+','K-','Kx'])

contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

subroutine leakage(W, l2)
	integer l1, l2; real Q, U(0:l2), V(0:l2), W(4,0:lmax)
	real, parameter :: twopi = 6.283185307179586476925286766559005768394338798750Q0
        
        alms = 0.0
        
        call random_number(U); call random_number(V)
        alms(1,l2,0:l2) = sqrt(-2.0*log(U)) * exp((0,twopi)*V)
        alms(2,l2,0:l2) = alms(1,l2,:)
        
        Q = sum(abs(alms(1,l2,0:l2)*alms(1,l2,0:l2)))/(2*l2+1)
        
        call alm2map(nside, lmax, lmax, alms, map)
        call map2alm_iterative(nside, lmax, lmax, 1, map, alms, mask=mask)
        
        do l1 = 0,lmax
                W(1,l1) = sum(abs(alms(1,l1,0:l1)*alms(1,l1,0:l1)))/Q
                W(2,l1) = sum(abs(alms(2,l1,0:l1)*alms(2,l1,0:l1)))/Q
                W(3,l1) = sum(abs(alms(3,l1,0:l1)*alms(3,l1,0:l1)))/Q
                W(4,l1) = sum(abs(alms(1,l1,0:l1)*alms(2,l1,0:l1)))/Q
        end do
end subroutine

end program