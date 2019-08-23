/*
 * MicroHH
 * Copyright (c) 2011-2018 Chiel van Heerwaarden
 * Copyright (c) 2011-2018 Thijs Heus
 * Copyright (c) 2014-2018 Bart van Stratum
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
#include <iostream>
#include <cstdio>
#include <cmath>
#include <algorithm>
#include "master.h"
#include "input.h"
#include "grid.h"
#include "fields.h"
#include "timeloop.h"
#include "timedep.h"
#include "defines.h"
#include "finite_difference.h"
#include "constants.h"
#include "tools.h"
#include "boundary.h"

using namespace Finite_difference::O4;

namespace
{
    template<typename TF> __global__
    void set_bc_value_g(TF* __restrict__ a, TF aval,
                  const int icells, const int jcells)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        if (i < icells && j < jcells)
        {
            const int ij  = i + j*icells;
            a[ij] = aval;
        }
    }


    template<typename TF> __global__
    void calc_ghost_cells_bot_2nd_g(TF* __restrict__ a, TF* __restrict__ dzh, Boundary_type sw,
                                    TF* __restrict__ abot, TF* __restrict__ agradbot,
                                    const int icells, const int jcells, const int kstart)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk  = icells*jcells;
        const int ij  = i + j*icells;
        const int ijk = i + j*icells + kstart*kk;

        if (i < icells && j < jcells)
        {
            if (sw == Boundary_type::Dirichlet_type)
                a[ijk-kk] = TF(2.)*abot[ij] - a[ijk];

            else if (sw == Boundary_type::Neumann_type || sw == Boundary_type::Flux_type)
                a[ijk-kk] = -agradbot[ij]*dzh[kstart] + a[ijk];
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_top_2nd_g(TF* __restrict__ a, TF* __restrict__ dzh, const Boundary_type sw,
                                    TF* __restrict__ atop, TF* __restrict__ agradtop,
                                    const int icells, const int jcells, const int kend)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk  = icells*jcells;
        const int ij  = i + j*icells;
        const int ijk = i + j*icells + (kend-1)*kk;

        if (i < icells && j < jcells)
        {
            if (sw == Boundary_type::Dirichlet_type)
                a[ijk+kk] = TF(2.)*atop[ij] - a[ijk];

            else if (sw == Boundary_type::Neumann_type || sw == Boundary_type::Flux_type)
                a[ijk+kk] = agradtop[ij]*dzh[kend] + a[ijk];
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_bot_4th_g(TF* __restrict__ a, TF* __restrict__ z, const Boundary_type sw,
                                    TF* __restrict__ abot, TF* __restrict__ agradbot,
                                    const int icells, const int jcells, const int kstart)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk1 = 1*icells*jcells;
        const int kk2 = 2*icells*jcells;

        const int ij  = i + j*icells;
        const int ijk = i + j*icells + kstart*kk1;

        if (i < icells && j < jcells)
        {
            if (sw == Boundary_type::Dirichlet_type)
            {
                a[ijk-kk1] = TF(8./3.)*abot[ij] - TF(2.)*a[ijk] + TF(1./3.)*a[ijk+kk1];
                a[ijk-kk2] = TF(8.)*abot[ij] - TF(9.)*a[ijk] + TF(2.)*a[ijk+kk1];
            }

            else if (sw == Boundary_type::Neumann_type || sw == Boundary_type::Flux_type)
            {
                a[ijk-kk1] = TF(-1.)*grad4(z[kstart-2], z[kstart-1], z[kstart], z[kstart+1])*agradbot[ij] + a[ijk    ];
                a[ijk-kk2] = TF(-3.)*grad4(z[kstart-2], z[kstart-1], z[kstart], z[kstart+1])*agradbot[ij] + a[ijk+kk1];
            }
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_top_4th_g(TF* __restrict__ a, TF* __restrict__ z,const Boundary_type sw,
                                    TF* __restrict__ atop, TF* __restrict__ agradtop,
                                    const int icells, const int jcells, const int kend)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk1 = 1*icells*jcells;
        const int kk2 = 2*icells*jcells;

        const int ij  = i + j*icells;
        const int ijk = i + j*icells + (kend-1)*kk1;

        if( i < icells && j < jcells)
        {
            if (sw == Boundary_type::Dirichlet_type)
            {
                a[ijk+kk1] = TF(8./3.)*atop[ij] - TF(2.)*a[ijk] + TF(1./3.)*a[ijk-kk1];
                a[ijk+kk2] = TF(8.)*atop[ij] - TF(9.)*a[ijk] + TF(2.)*a[ijk-kk1];
            }

            else if (sw == Boundary_type::Neumann_type || sw == Boundary_type::Flux_type)
            {
                a[ijk+kk1] = TF(1.)*grad4(z[kend-2], z[kend-1], z[kend], z[kend+1])*agradtop[ij] + a[ijk    ];
                a[ijk+kk2] = TF(3.)*grad4(z[kend-2], z[kend-1], z[kend], z[kend+1])*agradtop[ij] + a[ijk-kk1];
            }
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_botw_4th_g(TF* __restrict__ w,
                                      const int icells, const int jcells, const int kstart)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk1 = 1*icells*jcells;
        const int kk2 = 2*icells*jcells;
        const int kk3 = 3*icells*jcells;

        const int ijk = i + j*icells + kstart*kk1;

        if (i < icells && j < jcells)
        {
            w[ijk-kk1] = TF(-6.)*w[ijk+kk1] + TF(4.)*w[ijk+kk2] - w[ijk+kk3];
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_topw_4th_g(TF* __restrict__ w,
                                      const int icells, const int jcells, const int kend)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk1 = 1*icells*jcells;
        const int kk2 = 2*icells*jcells;
        const int kk3 = 3*icells*jcells;

        const int ijk = i + j*icells + kend*kk1;

        if (i < icells && j < jcells)
        {
            w[ijk+kk1] = TF(-6.)*w[ijk-kk1] + TF(4.)*w[ijk-kk2] - w[ijk-kk3];
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_botw_cons_4th_g(TF* __restrict__ w,
                                      const int icells, const int jcells, const int kstart)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk1 = 1*icells*jcells;
        const int kk2 = 2*icells*jcells;

        const int ijk = i + j*icells + kstart*kk1;

        if (i < icells && j < jcells)
        {
            w[ijk-kk1] = -w[ijk+kk1];
            w[ijk-kk2] = -w[ijk+kk2];
        }
    }

    template<typename TF> __global__
    void calc_ghost_cells_topw_cons_4th_g(TF* __restrict__ w,
                                      const int icells, const int jcells, const int kend)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x;
        const int j = blockIdx.y*blockDim.y + threadIdx.y;

        const int kk1 = 1*icells*jcells;
        const int kk2 = 2*icells*jcells;

        const int ijk = i + j*icells + kend*kk1;

        if (i < icells && j < jcells)
        {
            w[ijk+kk1] = -w[ijk-kk1];
            w[ijk+kk2] = -w[ijk-kk2];
        }
    }

    //Given a dataset of X and Y values, this function computes the slope and
    //and intercept of this dataset via linear regression
    template<typename TF> __global__
    TF* LinReg(const int istart, const int iend,const int jstart, const int jend,
        const int icells, const int ijcells, int k ,std::string boundary , TF* restrict data){

        const int jj = icells;
        const int kk = ijcells;

        TF avg_x=0;
        TF sum_squared_xdiff=0;
        TF inprod_xy=0;
        TF avg_y=0;

        if (boundary=="west"){
          int n = jend-jstart;
          for (int j=jstart; j<jend; j++){
            avg_x+=j;
          }
          avg_x /= n; //Computes the average of the x dataset
          for (int j=jstart;j<jend;j++) {
            const int ijkE = iend-1 + (j)*jj + k*kk;
            avg_y+=data[ijkE];
          }
          avg_y/=n;
          for (int j=jstart;j<jend;j++) {
            const int ijkE = iend-1 + (j)*jj + k*kk;
            inprod_xy+=(j-avg_x)*(data[ijkE]-avg_y);
            sum_squared_xdiff+=(j-avg_x)*(j-avg_x);
          }
        }

        else if (boundary=="east"){
          int n = jend-jstart;
          for (int j=jstart; j<jend; j++){
            avg_x+=j;
          }
          avg_x /= n; //Computes the average of the x dataset
          for (int j=jstart;j<jend;j++) {
            const int ijkW = istart + (j)*jj + k*kk;
            avg_y+=data[ijkW];
          }
          avg_y/=n;
          for (int j=jstart;j<jend;j++) {
            const int ijkW = istart + (j)*jj + k*kk;
            inprod_xy+=(j-avg_x)*(data[ijkW]-avg_y);
            sum_squared_xdiff+=(j-avg_x)*(j-avg_x);
          }
        }

        else if(boundary=="north"){
          int n = iend-istart;
          for (int i=istart; i<iend; i++){
            avg_x+=i;
          }
          avg_x /= n; //Computes the average of the x dataset
          for (int i=istart;i<iend;i++) {
            const int ijkS = i + (jstart)*jj + k*kk;
            avg_y+=data[ijkS];
          }
          avg_y/=n;
          for (int i=istart;i<iend;i++) {
            const int ijkS = i + (jstart)*jj + k*kk;
            inprod_xy+=(i-avg_x)*(data[ijkS]-avg_y);
            sum_squared_xdiff+=(i-avg_x)*(i-avg_x);
          }
        }

        else{
          int n = iend-istart;
          for (int i=istart; i<iend; i++){
            avg_x+=i;
          }
          avg_x /= n; //Computes the average of the x dataset
          for (int i=istart;i<iend;i++) {
            const int ijkN = i + (jend-1)*jj + k*kk;
            avg_y+=data[ijkN];
          }
          avg_y/=n;
          for (int i=istart;i<iend;i++) {
            const int ijkN = i + (jend-1)*jj + k*kk;
            inprod_xy+=(i-avg_x)*(data[ijkN]-avg_y);
            sum_squared_xdiff+=(i-avg_x)*(i-avg_x);
          }
        }

        TF *parameters=new TF[2];
        parameters[1] = inprod_xy / sum_squared_xdiff;//Slope determined by linear regression
        parameters[0] = avg_y - parameters[1] * avg_x;// Intercept determined by linear regression
        return parameters; //Returns a pointer to the array with the slope and intercept
                         //of the dataset determined by linear regression
    }
    template<typename TF> __global__
    void calc_regression(TF* restrict data, TF* corner0, TF* corner1, TF slope_data, TF intercept_data,
            const int i, const int jstart, const int kstart, const int icells, const int ijcells)
    {

        if (k < kend && j < jend)
        {
            const int ijk = i          + j*icells + k*ijcells;
            TF slope     = (corner1[k] - corner0[k]) / jtot - slope_data
            TF intercept = (corner0[k]) - intercept_data

            data[ijk] += slope*j + intercept;
        }
    }
    template<typename TF> __global__
    void calc_openbc_EW(TF* restrict data, TF* corner0, TF* corner1, TF slope_data, TF intercept_data,
            const int i, const int jstart, const int kstart, const int icells, const int ijcells)
    {
        const int j = blockIdx.y*blockDim.y + threadIdx.y + jstart;
        const int k = blockIdx.z + kstart;

        if (k < kend && j < jend)
        
        {
            const int ijk = i          + j*icells + k*ijcells;
            TF slope     = (corner1[k] - corner0[k]) / jtot - slope_data
            TF intercept = (corner0[k]) - intercept_data

            data[ijk] += slope*j + intercept;
        }
    }

    template<typename TF> __global__
    void calc_openbc_NS(TF* restrict data, TF* corner0, TF* corner1, TF slope_data, TF intercept_data,
            const int j, const int istart, const int kstart, const int icells, const int ijcells)
    {
        const int i = blockIdx.x*blockDim.x + threadIdx.x + istart;
        const int k = blockIdx.z + kstart;

        if (k < kend && i < iend)

        {
            const int ijk = i          + j*icells + k*ijcells;
            TF slope     = (corner1[k] - corner0[k]) / itot - slope_data
            TF intercept = (corner0[k]) - intercept_data

            data[ijk] += slope*i + intercept;
        }
    }

}

#ifdef USECUDA
template<typename TF>
void Boundary<TF>::exec(Thermo<TF>& thermo)
{
    auto& gd = grid.get_grid_data();

    const int blocki = gd.ithread_block;
    const int blockj = gd.jthread_block;
    const int gridi  = gd.icells/blocki + (gd.icells%blocki > 0);
    const int gridj  = gd.jcells/blockj + (gd.jcells%blockj > 0);

    dim3 grid2dGPU (gridi, gridj);
    dim3 block2dGPU(blocki, blockj);
    dim3 grid2dGPU (gridi, gridj);
    dim3 block2dGPU(blocki, blockj);

    dim3 gridxzGPU (gridi, gd.kcells);
    dim3 blockxzGPU(blocki, 1);
    dim3 gridyzGPU (gridj, gd.kcells);
    dim3 blockyzGPU(blockj, 1);
    // Cyclic boundary conditions, do this before the bottom BC's.
    boundary_cyclic.exec_g(fields.mp.at("u")->fld_g);
    boundary_cyclic.exec_g(fields.mp.at("v")->fld_g);
    boundary_cyclic.exec_g(fields.mp.at("w")->fld_g);

    for (auto& it : fields.sp)
        boundary_cyclic.exec_g(it.second->fld_g);

    if (swopenbc == Openbc_type::enabled)
        for (auto& it : openbc_list)
        {
            // West
            for (int i=0; i<=igc; ++i)
            {
                calc_openbc_EW<TF><<<gridyzGPU, blockyzGPU>>>(fields.ap.at(it)->fld_g, openbc_profs_g.at(it)->data[0*gd.kcells], openbc_profs_g.at(it)->data[2*gd.kcells], slope, intercept,
                    i, gd.jstart, gd.kstart, gd.icells, gd.ijcells)
            }
            // East
            for (int i=0; i<=igc; ++i)
            {
                calc_openbc_EW<TF><<<gridyzGPU, blockyzGPU>>>(fields.ap.at(it)->fld_g, openbc_profs_g.at(it)->data[1*gd.kcells], openbc_profs_g.at(it)->data[3*gd.kcells], slope, intercept,
                  i, gd.jstart, gd.kstart, gd.icells, gd.ijcells)
            }
            // South
            for (int j=0; j<=jgc; ++j)
            {
                calc_openbc_NS<TF><<<gridxzGPU, blockxzGPU>>>(fields.ap.at(it)->fld_g, openbc_profs_g.at(it)->data[0*gd.kcells], openbc_profs_g.at(it)->data[1*gd.kcells], slope, intercept,
                    j, gd.istart, gd.kstart, gd.icells, gd.ijcells)
            }
            // North
            for (int j=0; j<=jgc; ++j)
            {
                calc_openbc_NS<TF><<<gridxzGPU, blockxzGPU>>>(fields.ap.at(it)->fld_g, openbc_profs_g.at(it)->data[2*gd.kcells], openbc_profs_g.at(it)->data[3*gd.kcells], slope, intercept,
                    j, gd.istart, gd.kstart, gd.icells, gd.ijcells)
            }
        }

    // Calculate the boundary values.
    update_bcs(thermo);

    if (grid.get_spatial_order() == Grid_order::Second)
    {
        calc_ghost_cells_bot_2nd_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("u")->fld_g, gd.dzh_g, mbcbot,
            fields.mp.at("u")->fld_bot_g, fields.mp.at("u")->grad_bot_g,
            gd.icells, gd.jcells, gd.kstart);
        cuda_check_error();

        calc_ghost_cells_top_2nd_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("u")->fld_g, gd.dzh_g, mbctop,
            fields.mp.at("u")->fld_top_g, fields.mp.at("u")->grad_top_g,
            gd.icells, gd.jcells, gd.kend);
        cuda_check_error();

        calc_ghost_cells_bot_2nd_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("v")->fld_g, gd.dzh_g, mbcbot,
            fields.mp.at("v")->fld_bot_g, fields.mp.at("v")->grad_bot_g,
            gd.icells, gd.jcells, gd.kstart);
        cuda_check_error();

        calc_ghost_cells_top_2nd_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("v")->fld_g, gd.dzh_g, mbctop,
            fields.mp.at("v")->fld_top_g, fields.mp.at("v")->grad_top_g,
            gd.icells, gd.jcells, gd.kend);
        cuda_check_error();

        for (auto& it : fields.sp)
        {
            calc_ghost_cells_bot_2nd_g<TF><<<grid2dGPU, block2dGPU>>>(
                it.second->fld_g, gd.dzh_g, sbc.at(it.first).bcbot,
                it.second->fld_bot_g, it.second->grad_bot_g,
                gd.icells, gd.jcells, gd.kstart);
            cuda_check_error();

            calc_ghost_cells_top_2nd_g<TF><<<grid2dGPU, block2dGPU>>>(
                it.second->fld_g, gd.dzh_g, sbc.at(it.first).bctop,
                it.second->fld_top_g, it.second->grad_top_g,
                gd.icells, gd.jcells, gd.kend);
            cuda_check_error();
        }
    }
    else if (grid.get_spatial_order() == Grid_order::Fourth)
    {
        calc_ghost_cells_bot_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("u")->fld_g, gd.z_g, mbcbot,
            fields.mp.at("u")->fld_bot_g, fields.mp.at("u")->grad_bot_g,
            gd.icells, gd.jcells, gd.kstart);
        cuda_check_error();

        calc_ghost_cells_top_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("u")->fld_g, gd.z_g, mbctop,
            fields.mp.at("u")->fld_top_g, fields.mp.at("u")->grad_top_g,
            gd.icells, gd.jcells, gd.kend);
        cuda_check_error();

        calc_ghost_cells_bot_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("v")->fld_g, gd.z_g, mbcbot,
            fields.mp.at("v")->fld_bot_g, fields.mp.at("v")->grad_bot_g,
            gd.icells, gd.jcells, gd.kstart);
        cuda_check_error();

        calc_ghost_cells_top_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
            fields.mp.at("v")->fld_g, gd.z_g, mbctop,
            fields.mp.at("v")->fld_top_g, fields.mp.at("v")->grad_top_g,
            gd.icells, gd.jcells, gd.kend);
        cuda_check_error();

        for (auto& it : fields.sp)
        {
            calc_ghost_cells_bot_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
                it.second->fld_g, gd.z_g, sbc.at(it.first).bcbot,
                it.second->fld_bot_g, it.second->grad_bot_g,
                gd.icells, gd.jcells, gd.kstart);
            cuda_check_error();

            calc_ghost_cells_top_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
                it.second->fld_g, gd.z_g, sbc.at(it.first).bctop,
                it.second->fld_top_g, it.second->grad_top_g,
                gd.icells, gd.jcells, gd.kend);
            cuda_check_error();
        }
    }
}
#endif

template<typename TF>
void Boundary<TF>::prepare_device()
{
    auto& gd = grid.get_grid_data();

    const int nmemsize  = gd.kcells*sizeof(TF);

    if (swopenbc == Openbc_type::enabled)
    {
        for (auto& it : openbc_list)
        {
            openbc_profs_g.emplace(it, nullptr);
            cuda_safe_call(cudaMalloc(&openbc_profs_g.at(it), nmemsize));
            cuda_safe_call(cudaMemcpy(openbc_profs_g.at(it), openbc_profs.at(it).data(), nmemsize, cudaMemcpyHostToDevice));
        }
    }
}

template<typename TF>
void Boundary<TF>::clear_device()
{

    if (swopenbc == Openbc_type::enabled)
    {
        for (auto& it : openbc_profs_g)
            cuda_safe_call(cudaFree(it.second));
    }
    for(auto& it : tdep_bc)
        it.second->clear_device();
}

#ifdef USECUDA
template<typename TF>
void Boundary<TF>::set_ghost_cells_w(const Boundary_w_type boundary_w_type)
{
    auto& gd = grid.get_grid_data();
    const int blocki = gd.ithread_block;
    const int blockj = gd.jthread_block;
    const int gridi  = gd.icells/blocki + (gd.icells%blocki > 0);
    const int gridj  = gd.jcells/blockj + (gd.jcells%blockj > 0);

    dim3 grid2dGPU (gridi,  gridj );
    dim3 block2dGPU(blocki, blockj);

    if (grid.get_spatial_order() == Grid_order::Fourth)
    {
        if (boundary_w_type == Boundary_w_type::Normal_type)
        {
            calc_ghost_cells_botw_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
                fields.mp.at("w")->fld_g,
                gd.icells, gd.jcells, gd.kstart);
            cuda_check_error();

            calc_ghost_cells_topw_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
                fields.mp.at("w")->fld_g,
                gd.icells, gd.jcells, gd.kend);
            cuda_check_error();
        }
        else if (boundary_w_type == Boundary_w_type::Conservation_type)
        {
            calc_ghost_cells_botw_cons_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
                fields.mp.at("w")->fld_g,
                gd.icells, gd.jcells, gd.kstart);
            cuda_check_error();

            calc_ghost_cells_topw_cons_4th_g<TF><<<grid2dGPU, block2dGPU>>>(
                fields.mp.at("w")->fld_g,
                gd.icells, gd.jcells, gd.kend);
            cuda_check_error();
        }
    }
}
#endif

template<typename TF>
void Boundary<TF>::set_bc_g(TF* restrict a, TF* restrict agrad, TF* restrict aflux,
                        Boundary_type sw, TF aval, TF visc, TF offset)
{
    auto& gd = grid.get_grid_data();
    const int blocki = gd.ithread_block;
    const int blockj = gd.jthread_block;
    const int gridi  = gd.icells/blocki + (gd.icells%blocki > 0);
    const int gridj  = gd.jcells/blockj + (gd.jcells%blockj > 0);

    dim3 grid2dGPU (gridi, gridj);
    dim3 block2dGPU(blocki, blockj);

    if (sw == Boundary_type::Dirichlet_type)
    {
        set_bc_value_g<TF><<<grid2dGPU, block2dGPU>>>(a, aval-offset,    gd.icells, gd.jcells);
        cuda_check_error();
    }
    else if (sw == Boundary_type::Neumann_type)
    {
        set_bc_value_g<TF><<<grid2dGPU, block2dGPU>>>(agrad, aval,       gd.icells, gd.jcells);
        set_bc_value_g<TF><<<grid2dGPU, block2dGPU>>>(aflux, -aval*visc, gd.icells, gd.jcells);
        cuda_check_error();
    }
    else if (sw == Boundary_type::Flux_type)
    {
        set_bc_value_g<TF><<<grid2dGPU, block2dGPU>>>(aflux, aval,       gd.icells, gd.jcells);
        set_bc_value_g<TF><<<grid2dGPU, block2dGPU>>>(agrad, -aval*visc, gd.icells, gd.jcells);
        cuda_check_error();
    }
}

#ifdef USECUDA
template <typename TF>
void Boundary<TF>::update_time_dependent(Timeloop<TF>& timeloop)
{
    const Grid_data<TF>& gd = grid.get_grid_data();

    const TF no_offset = 0.;

    for (auto& it : tdep_bc)
    {
        it.second->update_time_dependent(sbc.at(it.first).bot,timeloop);
        set_bc_g(fields.sp.at(it.first)->fld_bot_g, fields.sp.at(it.first)->grad_bot_g, fields.sp.at(it.first)->flux_bot_g,
                sbc.at(it.first).bcbot, sbc.at(it.first).bot, fields.sp.at(it.first)->visc, no_offset);
    }
}
#endif

template class Boundary<double>;
template class Boundary<float>;
