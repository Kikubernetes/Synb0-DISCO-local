#!/bin/bash

# This script is based on pipeline.sh
# This is to run Synb0-DISCO on local computer.
# Prerequisites: You need to set up the following;
# - FreeSurfer
# - FSL
# - ANTs
# - c3d
# - PyTorch

# K. Nemoto 11 Aug 2022

TOPUP=1

for arg in "$@"
do
    case $arg in
        -i|--notopup)
        TOPUP=0
    esac
done


## Set path for executable
pipelinepath=$(cd $(dirname $0) && pwd)
synb0path=${pipelinepath%/src}
export Synb0_SRC=${synb0path}/src
export Synb0_PROC=${synb0path}/data_processing
export Synb0_ATLAS=${synb0path}/atlases
export PATH=$PATH:$Synb0_SRC:$Synb0_PROC:$Synb0_ATLAS


# Prepare input
prepare_input.sh ./INPUTS/b0.nii.gz ./INPUTS/T1.nii.gz ./INPUTS/T1_mask.nii.gz $Synb0_ATLAS/mni_icbm152_t1_tal_nlin_asym_09c.nii.gz $Synb0_ATLAS/mni_icbm152_t1_tal_nlin_asym_09c_2_5.nii.gz ./OUTPUTS


# Run inference
NUM_FOLDS=5
for i in $(seq 1 $NUM_FOLDS);
  do echo Performing inference on FOLD: "$i"
  python3 $Synb0_SRC/inference.py ./OUTPUTS/T1_norm_lin_atlas_2_5.nii.gz ./OUTPUTS/b0_d_lin_atlas_2_5.nii.gz ./OUTPUTS/b0_u_lin_atlas_2_5_FOLD_"$i".nii.gz $Synb0_SRC/train_lin/num_fold_"$i"_total_folds_"$NUM_FOLDS"_seed_1_num_epochs_100_lr_0.0001_betas_\(0.9\,\ 0.999\)_weight_decay_1e-05_num_epoch_*.pth
done


# Take mean
echo Taking ensemble average
fslmerge -t ./OUTPUTS/b0_u_lin_atlas_2_5_merged.nii.gz ./OUTPUTS/b0_u_lin_atlas_2_5_FOLD_*.nii.gz
fslmaths ./OUTPUTS/b0_u_lin_atlas_2_5_merged.nii.gz -Tmean ./OUTPUTS/b0_u_lin_atlas_2_5.nii.gz


# Apply inverse xform to undistorted b0
echo Applying inverse xform to undistorted b0
antsApplyTransforms -d 3 -i ./OUTPUTS/b0_u_lin_atlas_2_5.nii.gz -r ./INPUTS/b0.nii.gz -n BSpline -t [./OUTPUTS/epi_reg_d_ANTS.txt,1] -t [./OUTPUTS/ANTS0GenericAffine.mat,1] -o ./OUTPUTS/b0_u.nii.gz


# Smooth image
echo Applying slight smoothing to distorted b0
fslmaths ./INPUTS/b0.nii.gz -s 1.15 ./OUTPUTS/b0_d_smooth.nii.gz

if [[ $TOPUP -eq 1 ]]; then
    # Merge results and run through topup
    echo Running topup
    fslmerge -t ./OUTPUTS/b0_all.nii.gz ./OUTPUTS/b0_d_smooth.nii.gz ./OUTPUTS/b0_u.nii.gz
    topup -v --imain=./OUTPUTS/b0_all.nii.gz --datain=./INPUTS/acqparams.txt --config=b02b0.cnf --iout=./OUTPUTS/b0_all_topup.nii.gz --out=./OUTPUTS/topup --subsamp=1,1,1,1,1,1,1,1,1 --miter=10,10,10,10,10,20,20,30,30 --lambda=0.00033,0.000067,0.0000067,0.000001,0.00000033,0.000000033,0.0000000033,0.000000000033,0.00000000000067 --scale=0
fi


# Done
echo FINISHED!!!