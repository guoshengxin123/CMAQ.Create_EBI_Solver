
!------------------------------------------------------------------------!
!  The Community Multiscale Air Quality (CMAQ) system software is in     !
!  continuous development by various groups and is based on information  !
!  from these groups: Federal Government employees, contractors working  !
!  within a United States Government contract, and non-Federal sources   !
!  including research institutions.  These groups give the Government    !
!  permission to use, prepare derivative works of, and distribute copies !
!  of their work in the CMAQ system to the public and to permit others   !
!  to do so.  The United States Environmental Protection Agency          !
!  therefore grants similar permission to use the CMAQ system software,  !
!  but users are requested to provide copies of derivative works or      !
!  products designed to operate in the CMAQ system to the United States  !
!  Government without restrictions as to use by others.  Software        !
!  that is used with the CMAQ system but distributed under the GNU       !
!  General Public License or the GNU Lesser General Public License is    !
!  subject to their copyright restrictions.                              !
!------------------------------------------------------------------------!

C RCS file, release, date & time of last delta, author, state, [and locker]
C $Header$

C what(1) key, module and SID; SCCS file; date and time of last delta:
C %W% %P% %G% %U%

       SUBROUTINE CHEM( CGRID, JDATE, JTIME, TSTEP )

C**********************************************************************
C
C  FUNCTION: Driver subroutine for Euler Backward Iterative solver
C
R1  PRECONDITIONS: For the SAPRC99 family of mechanisms only
C
C  KEY SUBROUTINES/FUNCTIONS CALLED:  HRINIT, PHOT, HRCALCKS, HRSOLVER
R5C                                     FIND_DEGRADED, INIT_DEGRADE, FINAL_DEGRADE
C
R2  REVISION HISTORY: Prototype created by Jerry Gipson, September, 2003
C                       Based on the algorithm in "Test of Two Numerical
C                       Schemes for Use in Atmospheric Transport-Chemistry
C                       Models", O. Hertel, R. Berkowicz, J. Christensen,
C                       and O. Hov, Atm Env., Vol. 27A, No. 16, 1993.
C                       Original MEBI code developed by Ho-Chun Huang,
C                       SUNY, Albany -- "On the performance of numerical
C                       solvers for a chemistry submodel in three-dimensional 
C                       air quality models 1. Box model simulations", 
C                       H. Huang and J.S. Chang, JGR, Vol 106, No. D17, 2001.
C                       This version replaces Huang and Chang use of numerical
C                       solutions with analytical solutions derived in
C                       Hertel et al.
C   21 Jun 10 J.Young: convert for Namelist redesign
C   11 May 11 D.Wong: incorporated twoway model implementation
C   27 Sep 11 B.Hutzell: revised method for defining CALL_DEG variable
C                    
C**********************************************************************

      USE HGRD_DEFN             ! horizontal domain specifications
      USE VGRD_DEFN             ! vertical layer specifications      
      USE CGRID_SPCS            ! CGRID mechanism species
      USE UTILIO_DEFN           ! IOAPI parameters and functions declarations
      USE HRDATA

      IMPLICIT NONE 

C..Includes:
      INCLUDE SUBST_FILES_ID  ! CMAQ files
      INCLUDE SUBST_CONST     ! CMAQ constants
      INCLUDE SUBST_RXCMMN    ! Mechanism reaction common block
      INCLUDE SUBST_EMISPRM   ! Emissions processing control parameters
      INCLUDE SUBST_PACTL_ID  ! Process analysis control parameters

C..Arguments:
      REAL, POINTER :: CGRID( :,:,:,: )  ! Species concentrations
      INTEGER JDATE           ! Current date (YYYYDDD)
      INTEGER JTIME           ! Current time (HHMMSS)
      INTEGER TSTEP( 3 )      ! Time step vector (HHMMSS)

C..Parameters:
      REAL, PARAMETER :: PA2ATM = 1.0 / STDATMPA    ! Pascal to atm conv fac

C..External Functions:


C..Saved Local Variables:

      CHARACTER( 16 ), SAVE :: PNAME = 'HRDRIVER'     ! Program name

      INTEGER, SAVE :: ISTFL            ! Unit no. of iteration stat output file
      LOGICAL, SAVE :: LFIRST = .TRUE.  ! Flag for first call to this subroutine

      REAL, SAVE :: MAOMV               ! Mol Wt of air over Mol Wt of water

C..Scratch Local Variables:
      CHARACTER( 132 ) :: MSG           ! Message text
      CHARACTER(  16 ) :: VNAME         ! Name of I/O API data variable
      
      INTEGER C, E, L, R, S   ! Loop indices

      INTEGER AVGEBI          ! Average no. of EBI iterations
      INTEGER DELT_SEC        ! EBI max time step in seconds
      INTEGER ESP             ! Loop index for emissions species
      INTEGER ITMSTEP         ! Chemistry integration interval (sec)   
      INTEGER LEV             ! Layer index
      INTEGER MIDDATE         ! Date at time step midpoint
      INTEGER MIDTIME         ! Time at time step midpoint
      INTEGER MNEBI           ! Min no. of EBI iterations
      INTEGER MXEBI           ! Max no. of EBI iterations
      INTEGER NDARK           ! Number of layer 1 cells in darkness
      INTEGER NPH             ! Index for number of phot. rxns in PHOT
      INTEGER SPC             ! Species loop index
      INTEGER STATUS          ! Status code
      INTEGER VAR             ! Variable number on I/O API file
  
      LOGICAL LSUNLIGHT       ! Flag for sunlight

      REAL ATMPRES            ! Cell pressure
      REAL CHEMSTEP           ! Chemistry integration interval (min)
      REAL H2O                ! Cell H2O mixing ratio (ppmV)
      REAL SUMEBI             ! Sum of EBI iterations      
      REAL TEMP               ! Cell Temperature

R5      REAL DENS(    NCOLS, NROWS, NLAYS )        ! Cell mass density (Kg/m^3)
      REAL PRES(    NCOLS, NROWS, NLAYS )        ! Cell pressure (Pa)
      REAL QV(      NCOLS, NROWS, NLAYS )        ! Cell water vapor (Kg/Kg air)
      REAL TA(      NCOLS, NROWS, NLAYS )        ! Cell temperature (K)
      REAL RJIN( NPHOTAB )                       ! J-values for a cell
      REAL RJ( NCOLS, NROWS, NLAYS, NPHOTAB )    ! J-values for each cell      

      INTEGER     GXOFF, GYOFF            ! global origin offset from file
C for INTERPX
      INTEGER, SAVE :: STRTCOLMC3, ENDCOLMC3, STRTROWMC3, ENDROWMC3

R5      INTERFACE  ! for the degrade routines
R5         SUBROUTINE FIND_DEGRADED( JDATE, JTIME, LOGDEV, CALL_DEGRADE )
R5           USE DEGRADE_SETUP_TOX
R5           IMPLICIT NONE
R5           INTEGER, INTENT( IN )  :: JDATE        ! current model date , coded YYYYDDD
R5           INTEGER, INTENT( IN )  :: JTIME        ! current model time , coded HHMMSS
R5           INTEGER, INTENT( IN )  :: LOGDEV       ! unit number for the log file
R5           LOGICAL, INTENT( OUT ) :: CALL_DEGRADE ! whether to call degradation routines
R5         END SUBROUTINE FIND_DEGRADED
R5         SUBROUTINE INIT_DEGRADE( CBLK, TCELL, DCELL, PHOTO_CELL, JDATE, JTIME, LOGDEV )
R5           USE DEGRADE_SETUP_TOX
R5           IMPLICIT NONE
R5           INCLUDE SUBST_RXCMMN    ! Mechanism reaction common block
R5           REAL, INTENT( IN ) :: CBLK( NSPCSD )            !  species concentration in cell
R5           REAL, INTENT( IN ) :: TCELL                     !  cell temperature  [ k ]
R5           REAL, INTENT( IN ) :: DCELL                     !  cell air density  [ kg/m^3 ]
R5           REAL, INTENT( IN ) :: PHOTO_CELL( N_PHOTO_TAB ) !  Photolysis table for cell [1/s]
R5           INTEGER, INTENT( IN ) :: JDATE  ! current model date , coded YYYYDDD
R5           INTEGER, INTENT( IN ) :: JTIME  ! current model time , coded HHMMSS
R5           INTEGER, INTENT( IN ) :: LOGDEV ! unit number for the log
R5         END SUBROUTINE INIT_DEGRADE      
R5         SUBROUTINE FINAL_DEGRADE( CBLK )
R5           USE DEGRADE_SETUP_TOX
R5           IMPLICIT NONE
R5           REAL, INTENT( INOUT ) :: CBLK( NSPCSD )    !  species concentration in cell
R5         END SUBROUTINE FINAL_DEGRADE
R5       END INTERFACE

C**********************************************************************

      IF( N_GC_SPC .EQ. 0 ) RETURN

ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
c  On first call, call routines to set-up for EBI solver 
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
      IF( LFIRST ) THEN

         LOGDEV = INIT3( )

R3         IF( MECHNAME .NE. 'SAPRC99         ' .AND.
R3     &       MECHNAME .NE. 'SAPRC99_AQ      ' .AND.
R3     &       MECHNAME .NE. 'SAPRC99_AE      ' .AND.  
R3     &       MECHNAME .NE. 'SAPRC99_AE2     ' .AND. 
R3     &       MECHNAME .NE. 'SAPRC99_AE3     ' .AND.
R3     &       MECHNAME .NE. 'SAPRC99_AE4     ' .AND. 
R3     &       MECHNAME .NE. 'SAPRC99_AE_AQ   ' .AND.
R3     &       MECHNAME .NE. 'SAPRC99_AE2_AQ  ' .AND.
R3     &       MECHNAME .NE. 'SAPRC99_AE3_AQ  ' ) THEN
R3     &       MECHNAME .NE. 'SAPRC99_AE4_AQ  ' ) THEN
             MSG = 'This version of the EBI solver can only be used with' 
R4     &            // ' the SAPRC99 chemical mechanisms' 
             CALL M3EXIT( PNAME, 0, 0, MSG, XSTAT1 )
         END IF

#ifdef emis_chem
         EMISVD = .FALSE.
#else
         EMISVD = .TRUE.
#endif

         IF( INDEX( MECHNAME, 'AE' ) .NE. 0 ) THEN
           L_AE_VRSN = .TRUE.
         ELSE
           L_AE_VRSN = .FALSE.
         END IF

         IF( INDEX( MECHNAME, 'AQ' ) .NE. 0 ) THEN
           L_AQ_VRSN = .TRUE.
         ELSE
           L_AQ_VRSN = .FALSE.
         END IF

         IF( LIRR ) THEN
            MSG = 'IRR Analysis not allowed with EBI solver'
            CALL M3EXIT( PNAME, JDATE, JTIME, MSG, XSTAT1 )
         END IF 

R5         MODEL_SPECIES = NSPCSD    ! WTH: find number of model species
R5
R5! Determine whether DEGRADE rountines are needed.
R5
R5         CALL FIND_DEGRADED( JDATE, JTIME, LOGDEV, CALL_DEG )
R5         IF( CALL_DEG )THEN
R5            WRITE(LOGDEV,*)'TX DEGRADE ROUTINES USED'
R5            WRITE(LOGDEV,*)'Mechanism contains degraded species'
R5#ifdef verbose_gas
R5         ELSE
R5            WRITE(LOGDEV,*)'TX DEGRADE ROUTINES OMITTED'
R5            WRITE(LOGDEV,*)'MECHANISM does not include degraded species'
R5#endif
R5         END IF

         CALL HRINIT

         ITMSTEP = TIME2SEC( TSTEP( 2 ) )
         CHEMSTEP = FLOAT( ITMSTEP ) / 60.0
         WRITE( LOGDEV, 92000 ) CHEMSTEP, DELTAT

         WRITE( LOGDEV, 92020 )
         DO SPC = 1, N_GC_SPC
            WRITE( LOGDEV, 92040 ) GC_SPC( SPC ), RTOL( SPC )
         END DO

         MAOMV =  MWAIR / MWWAT

c..If emissions processing requested stop
         IF( .NOT. EMISVD ) THEN  ! assumes emis processing in gas chem

            MSG = 'ERROR: EBI solver not configured to '//
     &            'process emissions in chemistry'
            CALL M3EXIT( PNAME, JDATE, JTIME, MSG, XSTAT1 )

         END IF   ! End if doing emissions


#ifdef hrstats 
         ISTFL = JUNIT()
         OPEN( UNIT=ISTFL, FILE='iterstat.dat' )
         WRITE( ISTFL, 94020 )
#endif

         CALL SUBHFILE ( MET_CRO_3D, GXOFF, GYOFF,
     &                   STRTCOLMC3, ENDCOLMC3, STRTROWMC3, ENDROWMC3 )


         LFIRST = .FALSE.

      END IF      ! First time

ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
C  Set date and time to center of time step, get necessary physical 
C  data, and get photolysis rates
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
      MIDDATE = JDATE
      MIDTIME = JTIME
      ITMSTEP = TIME2SEC( TSTEP( 2 ) )
      CHEMSTEP = FLOAT( ITMSTEP ) / 60.0D+00
      CALL NEXTIME( MIDDATE, MIDTIME, SEC2TIME( ITMSTEP / 2 ) )

C.. Compute number of time step loops and step size for EBI solver
      DELT_SEC = DELTAT * 60.0 + 0.1
      IF( DELT_SEC .GE. ITMSTEP ) THEN
         N_EBI_STEPS = 1
         EBI_TMSTEP = FLOAT( ITMSTEP ) / 60.0
      ELSE
         IF( MOD( ITMSTEP, DELT_SEC ) .EQ. 0 ) THEN
            N_EBI_STEPS = ITMSTEP / DELT_SEC
         ELSE
            N_EBI_STEPS = ITMSTEP / DELT_SEC + 1
         END IF       
         EBI_TMSTEP =  FLOAT( ITMSTEP ) / FLOAT( N_EBI_STEPS ) / 60.0
      END IF       

      N_INR_STEPS = 1

 
C.. Get ambient temperature in K

      VNAME = 'TA' 
      IF ( .NOT. INTERPX( MET_CRO_3D, VNAME, PNAME,
     &                    STRTCOLMC3,ENDCOLMC3, STRTROWMC3,ENDROWMC3, 1,NLAYS,
     &                    MIDDATE, MIDTIME, TA ) ) THEN
         MSG = 'Could not read TA from MET_CRO_3D'
         CALL M3EXIT( PNAME, JDATE, JTIME, MSG, XSTAT1 )
      END IF
      
C.. Get specific humidity in Kg H2O / Kg air
      VNAME = 'QV'
      IF ( .NOT. INTERPX( MET_CRO_3D, VNAME, PNAME,
     &                    STRTCOLMC3,ENDCOLMC3, STRTROWMC3,ENDROWMC3, 1,NLAYS,
     &                    MIDDATE, MIDTIME, QV ) ) THEN
         MSG = 'Could not read QV from MET_CRO_3D'
         CALL M3EXIT( PNAME, JDATE, JTIME, MSG, XSTAT1 )
      END IF 

R5! Get ambient MASS DENSITY in Kg/m^3
R5       VNAME = 'DENS'
R5       IF ( .NOT. INTERPX( MET_CRO_3D, VNAME, PNAME,
R5     &                    STRTCOLMC3,ENDCOLMC3, STRTROWMC3,ENDROWMC3, 1,NLAYS,
R5     &                    MIDDATE, MIDTIME, DENS ) ) THEN
R5          MSG = 'Could not read DENS from MET_CRO_3D'
R5          CALL M3EXIT( PNAME, JDATE, JTIME, MSG, XSTAT1 )
R5       END IF
      
C.. Get pressure in Pascals
      VNAME = 'PRES'
      IF ( .NOT. INTERPX( MET_CRO_3D, VNAME, PNAME,
     &                    STRTCOLMC3,ENDCOLMC3, STRTROWMC3,ENDROWMC3, 1,NLAYS,
     &                    MIDDATE, MIDTIME, PRES ) ) THEN
         MSG = 'Could not read PRES from MET_CRO_3D'
         CALL M3EXIT ( PNAME, JDATE, JTIME, MSG, XSTAT1 )
      END IF
 
C.. Get photolysis rates in /min
      CALL PHOT ( MIDDATE, MIDTIME, JDATE, JTIME, NDARK, RJ )                    

ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
c  Top of loop over cells 
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

#ifdef hrstats 
      MNEBI = 1000
      MXEBI = 0
      SUMEBI = 0.0
#endif 

      DO L = 1, NLAYS
         DO R = 1, MY_NROWS
            DO C = 1, MY_NCOLS
 
c..Load ICs
               DO S = 1, N_GC_SPC
                  YC( S ) = MAX( CGRID( C, R, L, S ), 1.0E-30 )
               END DO

R5               IF(CALL_DEG)THEN ! INITIALIZE degradation routines
R5
R5                  YCCELL(1: MODEL_SPECIES) = CGRID(C,R,L,1: MODEL_SPECIES)
R5                  CALL INIT_DEGRADE(YCCELL,TA(C,R,L),DENS(C,R,L),RJIN,
R5     &                              JDATE, JTIME, LOGDEV)
R5               END IF

c..Set physical quantities
               TEMP = TA( C, R, L )
               ATMPRES = PA2ATM * PRES( C, R, L )
               H2O  = MAX ( QV( C, R, L ) * MAOMV *  1.0E+06, 0.0 )


c..Get rate constants
               LSUNLIGHT = .FALSE.
               DO NPH = 1, NPHOTAB
                  RJIN( NPH ) = RJ( C, R, L, NPH )
                  IF( RJ( C, R, L, NPH ) .GT. 0.0 ) LSUNLIGHT = .TRUE.
               END DO                         

               CALL HRCALCKS( NPHOTAB, LSUNLIGHT, RJIN, TEMP,
     &                        ATMPRES, H2O, RKI )


c..Call EBI solver
               N_EBI_IT = 0

               CALL HRSOLVER( JDATE, JTIME, C, R, L )

#ifdef hrstats 
               MXEBI  = MAX( MXEBI, N_EBI_IT )
               MNEBI  = MIN( MNEBI, N_EBI_IT )
               SUMEBI = SUMEBI + FLOAT( N_EBI_IT )
#endif
             

c..Update concentration array
               DO S = 1, N_GC_SPC 
                  CGRID( C, R, L, S ) = YC( S )
               END DO

R5               IF(CALL_DEG)THEN  ! WTH: update based on degrade routines
R5                  S = N_GC_SPC + 1
R5                  YCCELL(S:MODEL_SPECIES)     = CGRID(C,R,L,S:MODEL_SPECIES)
R5                  CALL FINAL_DEGRADE(YCCELL)
R5                  CGRID(C,R,L,S:MODEL_SPECIES) = YCCELL(S:MODEL_SPECIES)
R5               END IF

            END DO
         END DO
      END DO




#ifdef hrstats 
      AVGEBI = SUMEBI / FLOAT( NCOLS * NROWS * NLAYS )
      WRITE( ISTFL, 94040 ) JDATE, JTIME, MNEBI, AVGEBI, MXEBI
#endif

      RETURN

C*********************** FORMAT STATEMENTS ****************************

92000 FORMAT( / 10X, 'Euler Backward Iterative Parameters -'
     &        / 10X, 'Chemistry Integration Time Interval (min):', F12.4,
     &        / 10X, 'EBI maximum time step (min):              ', F12.4 )

92020 FORMAT( //10X, 'Species convergence tolerances:' )

92040 FORMAT(   10X, A16, 2X, 1PE12.2 )

92060 FORMAT( / 10X, 'Emissions Processing in Chemistry ...'
     &        / 10X, 'Number of Emissions Layers:         ', I3
     &        / 10X, 'out of total Number of Model Layers:', I3 )


94020 FORMAT( 'DATE      TIME ', 'MNEBI AVEBI MXEBI' )

94040 FORMAT( I7, 1X, I6, 1X, 3( I5, 1X ) )
      END
