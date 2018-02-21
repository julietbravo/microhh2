/*
 * MicroHH
 * Copyright (c) 2011-2017 Chiel van Heerwaarden
 * Copyright (c) 2011-2017 Thijs Heus
 * Copyright (c) 2014-2017 Bart van Stratum
 *
 * This file is part of MicroHH
 *
 * MicroHH is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * MicroHH is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with MicroHH.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "grid.h"
#include "tools.h"
#include "math.h"

namespace
{
    template<typename TF> __global__
    void boundary_cyclic_x_g(TF* const __restrict__ data,
                             const int icells, const int jcells, const int kcells,
                             const int icellsp,
                             const int istart, const int jstart,
                             const int iend,   const int jend,
                             const int igc,    const int jgc)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;
        const int k = blockIdx.z;

        const int jj = icellsp;
        const int kk = icellsp*jcells;

        // East-west
        if (k < kcells && j < jcells && i < igc)
        {
            const int ijk0 = i          + j*jj + k*kk;
            const int ijk1 = iend-igc+i + j*jj + k*kk;
            const int ijk2 = i+iend     + j*jj + k*kk;
            const int ijk3 = i+istart   + j*jj + k*kk;

            data[ijk0] = data[ijk1];
            data[ijk2] = data[ijk3];
        }
    }

    template<typename TF> __global__
    void boundary_cyclic_y_g(TF* const __restrict__ data,
                             const int icells, const int jcells, const int kcells,
                             const int icellsp,
                             const int istart, const int jstart,
                             const int iend,   const int jend,
                             const int igc,    const int jgc)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;
        const int k = blockIdx.z;

        const int jj = icellsp;
        const int kk = icellsp*jcells;

        // North-south
        if (jend-jstart == 1)
        {
            if (k < kcells && j < jgc && i < icells)
            {
                const int ijkref   = i + jstart*jj   + k*kk;
                const int ijknorth = i + j*jj        + k*kk;
                const int ijksouth = i + (jend+j)*jj + k*kk;
                data[ijknorth] = data[ijkref];
                data[ijksouth] = data[ijkref];
            }
        }
        else
        {
            if (k < kcells && j < jgc && i < icells)
            {
                const int ijk0 = i + j           *jj + k*kk;
                const int ijk1 = i + (jend-jgc+j)*jj + k*kk;
                const int ijk2 = i + (j+jend  )  *jj + k*kk;
                const int ijk3 = i + (j+jstart)  *jj + k*kk;

                data[ijk0] = data[ijk1];
                data[ijk2] = data[ijk3];
            }
        }
    }
}

template<typename TF>
void Grid<TF>::prepare_device()
{
    /* Align the interior of the grid (i.e. excluding ghost cells) with
       the 128 byte memory blocks of the GPU's global memory */
    gd.memoffset = 16 - gd.igc;           // Padding at start of array
    int padl     = 16-(int)gd.imax%16;    // Elements left in last 128 byte block
    gd.icellsp   = gd.imax + padl + (padl < 2*gd.igc) * 16;
    gd.ijcellsp  = gd.icellsp * gd.jcells;
    gd.ncellsp   = gd.ijcellsp * gd.kcells + gd.memoffset;

    // Calculate optimal size thread blocks based on grid
    gd.ithread_block = min(256, 16 * ((gd.itot / 16) + (gd.itot % 16 > 0)));
    gd.jthread_block = 256 / gd.ithread_block;

    const int kmemsize = gd.kcells*sizeof(TF);

    cuda_safe_call(cudaMalloc((void**)&gd.z_g    , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.zh_g   , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.dz_g   , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.dzh_g  , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.dzi_g  , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.dzhi_g , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.dzi4_g , kmemsize));
    cuda_safe_call(cudaMalloc((void**)&gd.dzhi4_g, kmemsize));

    cuda_safe_call(cudaMemcpy(gd.z_g    , gd.z.data()    , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.zh_g   , gd.zh.data()   , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.dz_g   , gd.dz.data()   , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.dzh_g  , gd.dzh.data()  , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.dzi_g  , gd.dzi.data()  , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.dzhi_g , gd.dzhi.data() , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.dzi4_g , gd.dzi4.data() , kmemsize, cudaMemcpyHostToDevice));
    cuda_safe_call(cudaMemcpy(gd.dzhi4_g, gd.dzhi4.data(), kmemsize, cudaMemcpyHostToDevice));
}

template<typename TF>
void Grid<TF>::clear_device()
{
    cuda_safe_call(cudaFree(gd.z_g    ));
    cuda_safe_call(cudaFree(gd.zh_g   ));
    cuda_safe_call(cudaFree(gd.dz_g   ));
    cuda_safe_call(cudaFree(gd.dzh_g  ));
    cuda_safe_call(cudaFree(gd.dzi_g  ));
    cuda_safe_call(cudaFree(gd.dzhi_g ));
    cuda_safe_call(cudaFree(gd.dzi4_g ));
    cuda_safe_call(cudaFree(gd.dzhi4_g));
}

template<typename TF>
void Grid<TF>::boundary_cyclic_g(TF* data)
{
    const int blocki_x = gd.igc;
    const int blockj_x = 256 / gd.igc + (256%gd.igc > 0);
    const int gridi_x  = 1;
    const int gridj_x  = gd.jcells/blockj_x + (gd.jcells%blockj_x > 0);

    const int blocki_y = 256 / gd.jgc + (256%gd.jgc > 0);
    const int blockj_y = gd.jgc;
    const int gridi_y  = gd.icells/blocki_y + (gd.icells%blocki_y > 0);
    const int gridj_y  = 1;

    dim3 gridGPUx (gridi_x,  gridj_x,  gd.kcells);
    dim3 blockGPUx(blocki_x, blockj_x, 1);

    dim3 gridGPUy (gridi_y,  gridj_y,  gd.kcells);
    dim3 blockGPUy(blocki_y, blockj_y, 1);

    boundary_cyclic_x_g<TF><<<gridGPUx,blockGPUx>>>(
        data, gd.icells, gd.jcells, gd.kcells, gd.icellsp,
        gd.istart, gd.jstart, gd.iend, gd.jend, gd.igc, gd.jgc);

    boundary_cyclic_y_g<TF><<<gridGPUy,blockGPUy>>>(
        data, gd.icells, gd.jcells, gd.kcells, gd.icellsp,
        gd.istart, gd.jstart, gd.iend, gd.jend, gd.igc, gd.jgc);

    cuda_check_error();
}

template<typename TF>
void Grid<TF>::boundary_cyclic2d_g(TF* data)
{
    const int blocki_x = gd.igc;
    const int blockj_x = 256 / gd.igc + (256%gd.igc > 0);
    const int gridi_x  = 1;
    const int gridj_x  = gd.jcells/blockj_x + (gd.jcells%blockj_x > 0);

    const int blocki_y = 256 / gd.jgc + (256%gd.jgc > 0);
    const int blockj_y = gd.jgc;
    const int gridi_y  = gd.icells/blocki_y + (gd.icells%blocki_y > 0);
    const int gridj_y  = 1;

    dim3 gridGPUx (gridi_x,  gridj_x,  1);
    dim3 blockGPUx(blocki_x, blockj_x, 1);

    dim3 gridGPUy (gridi_y,  gridj_y,  1);
    dim3 blockGPUy(blocki_y, blockj_y, 1);

    boundary_cyclic_x_g<TF><<<gridGPUx,blockGPUx>>>(
        data, gd.icells, gd.jcells, gd.kcells, gd.icellsp,
        gd.istart, gd.jstart, gd.iend, gd.jend, gd.igc, gd.jgc);

    boundary_cyclic_y_g<TF><<<gridGPUy,blockGPUy>>>(
        data, gd.icells, gd.jcells, gd.kcells, gd.icellsp,
        gd.istart, gd.jstart, gd.iend, gd.jend, gd.igc, gd.jgc);

    cuda_check_error();
}

template class Grid<double>;
template class Grid<float>;