function [rowdG, coldG, dG, rowG, resG] = CFD_Assemble_SUPG_Impl(...
    dim, elements, detjac, invjac, ...
    w, phi, dphiref, nln, ...
    U_k, v_n, density, viscosity, dt, alpha)
%CFD_ASSEMBLE_SUPG_IMPL SUPG stabilization assembler for unsteady 2D/3D
%NS equations with implicit BDF integrator and Newton iterations. Only for P1 FEM.
% 
%   The stabilization is implemented as formulated in the Variational 
%   MultiScale framework. 
%
%   ----------------------------------------------------------------------
%   For reference see paper:
%   "Variational multiscale residual-based turbulence modeling for
%   large eddy simulation of incompressible ﬂows" by Bazilevs et al., 2007.
%   ----------------------------------------------------------------------

%   This file is part of redbKIT.
%   Copyright (c) 2016, Ecole Polytechnique Federale de Lausanne (EPFL)
%   Author: Federico Negri <federico.negri at epfl.ch>

switch dim
   
    case 2
        [rowdG, coldG, dG, rowG, resG] = CFD_Assemble_SUPG_Impl_2D(...
            elements, detjac, invjac, ...
            w, phi, dphiref, nln, ...
            U_k, v_n, density, viscosity, dt, alpha);
        
    case 3
        [rowdG, coldG, dG, rowG, resG] = CFD_Assemble_SUPG_Impl_3D(...
            elements, detjac, invjac, ...
            w, phi, dphiref, nln, ...
            U_k, v_n, density, viscosity, dt, alpha);
        
    otherwise
        
        rowdG = -1;
        coldG = -1; 
        dG    = -1; 
        rowG  = -1; 
        resG  = -1;
end

end

%==========================================================================
function [rowdG, coldG, dG, rowG, resG] = CFD_Assemble_SUPG_Impl_2D(...
    elements, detjac, invjac, ...
    w, phi, dphiref, nln, ...
    U_k, v_n, density, viscosity, dt, alpha)

nov = length(v_n) / 2;

dcdx = invjac(:,1,1);
dedx = invjac(:,1,2);
dcdy = invjac(:,2,1);
dedy = invjac(:,2,2);

dxphi = dphiref(:,:,1);
dyphi = dphiref(:,:,2);

rho = density;

us   = U_k(1:2*nov);
ph   = U_k(1+2*nov:3*nov);

nln2 = nln*nln;

noe          = size(elements, 2);
rowdG        = zeros(9*nln2*noe,1);
coldG        = rowdG;
dG           = zeros(9*nln2*noe,1);

rowG         = zeros(3*nln*noe,1);
resG         = zeros(3*nln*noe,1);

[rows,cols]  = meshgrid(1:nln,1:nln);
rows         = rows(:);
cols         = cols(:);

one          = ones(nln, 1);

iii          = 1:nln2;
i_all        = 1:9*nln2;
ii           = 1:3*nln;

FZ           = zeros(nln,1);

w_nln        = w(one,:);

for ie = 1 : noe
      
      e     = elements(1:nln,ie);
      
      % evaluate velocity u_h in the quadrature nodes
      uhq   = (us(e)'*phi);
      vhq   = (us(e+nov)'*phi);
      uhq   = uhq(one,:);
      vhq   = vhq(one,:);
     
      % evaluate velocity u_n in the quadrature nodes
      unq = (v_n(e)'*phi);
      vnq = (v_n(e+nov)'*phi);
      unq = unq(one,:);
      vnq = vnq(one,:);
      
      % compute derivatives in the element
      gradx = dcdx(ie)*dxphi + dedx(ie)*dyphi;
      grady = dcdy(ie)*dxphi + dedy(ie)*dyphi;
      
      % evaluate velocity d(u_n)/dx and d(u_n)/dy in the quadrature nodes 
      uhdx = us(e)' * gradx; 
      uhdx = uhdx(one,:);
      uhdy = us(e)' * grady; 
      uhdy = uhdy(one,:);
      
      vhdx = us(e+nov)' * gradx; 
      vhdx = vhdx(one,:);
      vhdy = us(e+nov)' * grady; 
      vhdy = vhdy(one,:);
      
      % evaluate pressure gradient in the quadrature nodes
      phdx = ph(e)' * gradx; 
      phdx = phdx(one,:);
      phdy = ph(e)' * grady; 
      phdy = phdy(one,:);
      
      % compute metric tensors G and g
      G     =  [dcdx(ie) dcdy(ie) ; dedx(ie) dedy(ie)];       
      g     =  [dcdx(ie) + dedx(ie) ; dcdy(ie) + dedy(ie)];
      
      G     =  G'*G;
      u_f   =  [uhq(1,:); vhq(1,:)];
      
      % compute tabilization parameters tauM and tuaC in the quadratures
      % nodes
      tauM  =  ( 4*rho^2/dt^2 + rho^2 * diag(u_f'*(G*u_f))' + 30*viscosity^2*trace(G'*G)).^(-0.5);
      
      tauC  =  1./(tauM * (g'*g)); 
      
      % multiply them by the quadratures weights w_nln
      tauM  = tauM(one,:).*w_nln;
      tauC  = tauC(one,:).*w_nln;
      
      % compute 1st and 2nd component of the residual R_M evaluated in (u_h, p_h)
      R_M1  =  rho/dt*(alpha*uhq - unq) + rho*(uhq.*uhdx + vhq.*uhdy) + phdx;
      R_M2  =  rho/dt*(alpha*vhq - vnq) + rho*(uhq.*vhdx + vhq.*vhdy) + phdy;
      
      % compute residual R_C evaluated in u_h
      R_C   =  uhdx + vhdy;
      
      uh_gradPHI       = rho*(uhq.*gradx + vhq.*grady);
      uh_gradPHI_tauM  = tauM.*uh_gradPHI;
      
      tmp = rho*phi.*(tauM.*R_M1);
      aloc_MtauM11  = tmp*gradx' + ...
                        (rho*alpha/dt*phi + rho*phi.*uhdx + uh_gradPHI)*uh_gradPHI_tauM';
      
      aloc_MtauM12  = tmp*grady' + ...
                        (rho*phi.*uhdy)*uh_gradPHI_tauM';
      
      tmp = rho*phi.*(tauM.*R_M2);
      aloc_MtauM21  = tmp*gradx' + ...
                        (rho*phi.*vhdx)*uh_gradPHI_tauM';
      
      aloc_MtauM22  = tmp*grady' + ...
                        (rho*alpha/dt*phi + rho*phi.*vhdy + uh_gradPHI)*uh_gradPHI_tauM';
      
      aloc_MtauM13  = gradx*uh_gradPHI_tauM';
      
      aloc_MtauM23  = grady*uh_gradPHI_tauM';

      aloc_MtauC11 =  tauC.*gradx*gradx';
      aloc_MtauC12 =  tauC.*grady*gradx';
      aloc_MtauC21 =  tauC.*gradx*grady';
      aloc_MtauC22 =  tauC.*grady*grady';

      aloc_CtauM31 = ( (rho*alpha/dt*phi + rho*phi.*uhdx + uh_gradPHI ).*tauM*gradx' + rho*(phi.*vhdx).*tauM*grady' );
      aloc_CtauM32 = ( (rho*alpha/dt*phi + rho*phi.*vhdy + uh_gradPHI ).*tauM*grady' + rho*(phi.*uhdy).*tauM*gradx' );
      aloc_CtauM33 = (gradx.*tauM)*gradx' + (grady.*tauM)*grady';
      
      aloc11 = aloc_MtauM11 + aloc_MtauC11;
      aloc12 = aloc_MtauM12 + aloc_MtauC12;
      aloc13 = aloc_MtauM13;
      aloc21 = aloc_MtauM21 + aloc_MtauC21;
      aloc22 = aloc_MtauM22 + aloc_MtauC22;
      aloc23 = aloc_MtauM23;
      aloc31 =                                aloc_CtauM31;
      aloc32 =                                aloc_CtauM32;
      aloc33 =                                aloc_CtauM33;
      
      res_MtauC  = [ ((tauC(1,:).*R_C(1,:)) *gradx')' ;
                     ((tauC(1,:).*R_C(1,:)) *grady')' ;
                      FZ                             ];
           
      res_CtauM3  = gradx * (tauM(1,:).*R_M1(1,:))' + grady*(tauM(1,:).*R_M2(1,:))';
      
      res_CtauM   =  [ FZ     ; ...
                       FZ     ; ...
                       res_CtauM3];    
      
      res_MtauM   =  [uh_gradPHI * (tauM(1,:).*R_M1(1,:))'; ...
                      uh_gradPHI * (tauM(1,:).*R_M2(1,:))';...
                      FZ                                                 ];
      
      res_SUPG    = res_MtauM + res_MtauC + res_CtauM;
      
      % local to global matrices
      rr    = elements(rows,ie)';
      tt    = elements(cols,ie)';
      
      ac11  = aloc11(:)*detjac(ie);
      ac12  = aloc12(:)*detjac(ie);
      ac13  = aloc13(:)*detjac(ie);
      ac21  = aloc21(:)*detjac(ie);
      ac22  = aloc22(:)*detjac(ie);
      ac23  = aloc23(:)*detjac(ie);
      ac31  = aloc31(:)*detjac(ie);
      ac32  = aloc32(:)*detjac(ie);
      ac33  = aloc33(:)*detjac(ie);
      
      rowdG(i_all)  = [rr rr rr rr+nov rr+nov rr+nov rr+2*nov rr+2*nov rr+2*nov];
      coldG(i_all)  = [tt tt+nov tt+2*nov tt tt+nov tt+2*nov tt tt+nov tt+2*nov];
      dG(i_all)     = [ac11; ac12; ac13; ac21; ac22; ac23; ac31; ac32; ac33];
      
      dof_ie        = elements(1:nln,ie);
      rowG(ii)      = [dof_ie; nov+dof_ie; 2*nov+dof_ie];
      
      resG(ii)      = res_SUPG*detjac(ie); 
      
      i_all         = i_all + 9*nln2;
      iii           = iii + nln2;
      ii            = ii  + 3*nln;
end

end
%==========================================================================
function [rowdG, coldG, dG, rowG, resG] = CFD_Assemble_SUPG_Impl_3D(...
    elements, detjac, invjac, ...
    w, phi, dphiref, nln, ...
    U_k, v_n, density, viscosity, dt, alpha)

nov = length(v_n) / 3;

dcdx = invjac(:,1,1);
dedx = invjac(:,1,2);
dtdx = invjac(:,1,3);
dcdy = invjac(:,2,1);
dedy = invjac(:,2,2);
dtdy = invjac(:,2,3);
dcdz = invjac(:,3,1);
dedz = invjac(:,3,2);
dtdz = invjac(:,3,3);

dxphi = dphiref(:,:,1);
dyphi = dphiref(:,:,2);
dzphi = dphiref(:,:,3);

rho = density;

noe = size(elements,2);

us   = U_k(1:3*nov);
ph   = U_k(1+3*nov:4*nov);
nln2 = nln*nln;

n_blocks  = 4;
n_blocks2 = n_blocks^2;

rowdG        = zeros(n_blocks2*nln2*noe,1);
coldG        = rowdG;
dG           = zeros(n_blocks2*nln2*noe,1);

rowG         = zeros(n_blocks*nln*noe,1);
resG         = zeros(n_blocks*nln*noe,1);

[rows,cols]  = meshgrid(1:nln,1:nln);
rows         = rows(:);
cols         = cols(:);

one          = ones(nln, 1);

iii          = 1:nln2;
i_all        = 1:n_blocks2*nln2;
ii           = 1:n_blocks*nln;

FZ           = zeros(nln,1);

w_nln        = w(one,:);

for ie = 1 : noe
      
      e     = elements(1:nln,ie);
      
      % evaluate velocity u_h in the quadrature nodes
      uhq   = (us(e)'*phi);
      vhq   = (us(e+nov)'*phi);
      whq   = (us(e+2*nov)'*phi);
      uhq   = uhq(one,:);
      vhq   = vhq(one,:);
      whq   = whq(one,:);
     
      % evaluate velocity u_n in the quadrature nodes
      unq   = (v_n(e)'*phi);
      vnq   = (v_n(e+nov)'*phi);
      unq   = unq(one,:);
      vnq   = vnq(one,:);
      wnq   = (v_n(e+2*nov)'*phi);
      wnq   = wnq(one,:);
      
      % compute derivatives in the element
      gradx = dcdx(ie)*dxphi + dedx(ie)*dyphi + dtdx(ie)*dzphi;
      grady = dcdy(ie)*dxphi + dedy(ie)*dyphi + dtdy(ie)*dzphi;
      gradz = dcdz(ie)*dxphi + dedz(ie)*dyphi + dtdz(ie)*dzphi;
      
      % evaluate velocity d(u_n)/dx, d(u_n)/dy and d(u_n)/dz in the quadrature nodes 
      uhdx = us(e)' * gradx; uhdx = uhdx(one,:);
      uhdy = us(e)' * grady; uhdy = uhdy(one,:);
      uhdz = us(e)' * gradz; uhdz = uhdz(one,:);
      
      vhdx = us(e+nov)' * gradx; vhdx = vhdx(one,:);
      vhdy = us(e+nov)' * grady; vhdy = vhdy(one,:);
      vhdz = us(e+nov)' * gradz; vhdz = vhdz(one,:);
      
      whdx = us(e+2*nov)' * gradx; whdx = whdx(one,:);
      whdy = us(e+2*nov)' * grady; whdy = whdy(one,:);
      whdz = us(e+2*nov)' * gradz; whdz = whdz(one,:);

      
      % evaluate pressure gradient in the quadrature nodes
      phdx = ph(e)' * gradx; phdx = phdx(one,:);
      phdy = ph(e)' * grady; phdy = phdy(one,:);
      phdz = ph(e)' * gradz; phdz = phdz(one,:);
      
      % compute metric tensors G and g
      G     = [dcdx(ie) dcdy(ie) dcdz(ie); dedx(ie) dedy(ie) dedz(ie); dtdx(ie) dtdy(ie) dtdz(ie)];
       
      g     =  [dcdx(ie) + dedx(ie) + dtdx(ie); dcdy(ie) + dedy(ie) + dtdy(ie); dcdz(ie) + dedz(ie) + dtdz(ie)];
      
      G     =  G'*G;
      u_f   =  [uhq(1,:); vhq(1,:); whq(1,:)];
      
      % compute tabilization parameters tauM and tuaC in the quadratures
      % nodes
      
      tauM  =  ( 4*rho^2/dt^2 + rho^2*diag(u_f'*(G*u_f))' + 30*viscosity^2*trace(G'*G)).^(-0.5);
      
      tauC  =  1./(tauM * (g'*g));
      
      % multiply them by the quadratures weights w_nln
      tauM  = tauM(one,:).*w_nln;
      tauC  = tauC(one,:).*w_nln;
      
      % compute 1st and 2nd component of the residual R_M evaluated in (u_h, p_h)
      R_M1  =  rho/dt*(alpha*uhq - unq) + rho*(uhq.*uhdx + vhq.*uhdy + whq.*uhdz) + phdx;
      R_M2  =  rho/dt*(alpha*vhq - vnq) + rho*(uhq.*vhdx + vhq.*vhdy + whq.*vhdz) + phdy;
      R_M3  =  rho/dt*(alpha*whq - wnq) + rho*(uhq.*whdx + vhq.*whdy + whq.*whdz) + phdz;
      
      % compute residual R_C evaluated in u_h
      R_C   =  uhdx + vhdy + whdz;
      
      uh_gradPHI       = rho*(uhq.*gradx + vhq.*grady + whq.*gradz);
      uh_gradPHI_tauM  = tauM.*uh_gradPHI;
      
      aloc_MtauM11  = rho*phi.*(tauM.*R_M1)*gradx' + ...
            [rho*alpha/dt*phi + rho*phi.*uhdx + uh_gradPHI]*uh_gradPHI_tauM';
      
      aloc_MtauM12  = rho*phi.*(tauM.*R_M1)*grady' + ...
            [rho*phi.*uhdy]*uh_gradPHI_tauM';
      
      aloc_MtauM13  = rho*phi.*(tauM.*R_M1)*gradz' + ...
            [rho*phi.*uhdz]*uh_gradPHI_tauM';
      
      aloc_MtauM21  = rho*phi.*(tauM.*R_M2)*gradx' + ...
            [rho*phi.*vhdx]*uh_gradPHI_tauM';
      
      aloc_MtauM23  = rho*phi.*(tauM.*R_M2)*gradz' + ...
            [rho*phi.*vhdz]*uh_gradPHI_tauM';
      
      aloc_MtauM22  = rho*phi.*(tauM.*R_M2)*grady' + ...
            [rho*alpha/dt*phi + rho*phi.*vhdy + uh_gradPHI]*uh_gradPHI_tauM';
      
      aloc_MtauM31  = rho*phi.*(tauM.*R_M3)*gradx' + ...
            [rho*phi.*whdx]*uh_gradPHI_tauM';
      
      aloc_MtauM32  = rho*phi.*(tauM.*R_M3)*grady' + ...
            [rho*phi.*whdy]*uh_gradPHI_tauM';
      
      aloc_MtauM33  = rho*phi.*(tauM.*R_M3)*gradz' + ...
            [rho*alpha/dt*phi + rho*phi.*whdz + uh_gradPHI]*uh_gradPHI_tauM';
      
      
      aloc_MtauM14  = gradx*uh_gradPHI_tauM';
      
      aloc_MtauM24  = grady*uh_gradPHI_tauM';
      
      aloc_MtauM34  = gradz*uh_gradPHI_tauM';
      
      
      aloc_MtauC11 =  (tauC.*gradx)*gradx';
      aloc_MtauC12 =  (tauC.*grady)*gradx';
      aloc_MtauC13 =  (tauC.*gradz)*gradx';
      aloc_MtauC21 =  (tauC.*gradx)*grady';
      aloc_MtauC22 =  (tauC.*grady)*grady';
      aloc_MtauC23 =  (tauC.*gradz)*grady';
      aloc_MtauC31 =  (tauC.*gradx)*gradz';
      aloc_MtauC32 =  (tauC.*grady)*gradz';
      aloc_MtauC33 =  (tauC.*gradz)*gradz';
      
      
      aloc_CtauM41 = ( ((rho*alpha/dt*phi + rho*phi.*uhdx + uh_gradPHI).*tauM)*gradx' + rho*(phi.*vhdx).*tauM*grady' + rho*(phi.*whdx).*tauM*gradz' );
      aloc_CtauM42 = ( ((rho*alpha/dt*phi + rho*phi.*vhdy + uh_gradPHI).*tauM)*grady' + rho*(phi.*uhdy).*tauM*gradx' + rho*(phi.*whdy).*tauM*gradz');
      aloc_CtauM43 = ( ((rho*alpha/dt*phi + rho*phi.*whdz + uh_gradPHI).*tauM)*gradz' + rho*(phi.*uhdz).*tauM*gradx' + rho*(phi.*vhdz).*tauM*grady' );
      
      aloc_CtauM44 = (gradx.*tauM)*gradx' + (grady.*tauM)*grady' + (gradz.*tauM)*gradz';
      
      
      aloc11 = aloc_MtauM11 + aloc_MtauC11;
      aloc12 = aloc_MtauM12 + aloc_MtauC12;
      aloc13 = aloc_MtauM13 + aloc_MtauC13;
      aloc14 = aloc_MtauM14;
      
      aloc21 = aloc_MtauM21 + aloc_MtauC21;
      aloc22 = aloc_MtauM22 + aloc_MtauC22;
      aloc23 = aloc_MtauM23 + aloc_MtauC23;
      aloc24 = aloc_MtauM24;
      
      aloc31 = aloc_MtauM31 + aloc_MtauC31;
      aloc32 = aloc_MtauM32 + aloc_MtauC32;
      aloc33 = aloc_MtauM33 + aloc_MtauC33;
      aloc34 = aloc_MtauM34;
      
      aloc41 =                            aloc_CtauM41;
      aloc42 =                            aloc_CtauM42;
      aloc43 =                            aloc_CtauM43;
      aloc44 =                            aloc_CtauM44;
      
      
      res_MtauC  = [ ((tauC(1,:).*R_C(1,:)) *gradx')' ;
                     ((tauC(1,:).*R_C(1,:)) *grady')' ;
                     ((tauC(1,:).*R_C(1,:)) *gradz')' ;
                      FZ                             ];
           
      
      res_CtauM4  = gradx * (tauM(1,:).*R_M1(1,:))' + ...
                    grady * (tauM(1,:).*R_M2(1,:))' + ...
                    gradz * (tauM(1,:).*R_M3(1,:))';
      
      
      res_CtauM   =  [ FZ     ; ...
                       FZ     ; ...
                       FZ     ; ...
                       res_CtauM4];    
      
      
      res_MtauM   =  [ uh_gradPHI * (tauM(1,:).*R_M1(1,:))';...
                       uh_gradPHI * (tauM(1,:).*R_M2(1,:))';...
                       uh_gradPHI * (tauM(1,:).*R_M3(1,:))';...
                       FZ                                                 ];
                 
      res_SUPG    = res_MtauM + res_MtauC + res_CtauM;
      
      
      % local to global matrices
      rr    = elements(rows,ie)';
      tt    = elements(cols,ie)';
      
      ac11  = aloc11(:)*detjac(ie);
      ac12  = aloc12(:)*detjac(ie);
      ac13  = aloc13(:)*detjac(ie);
      ac14  = aloc14(:)*detjac(ie);
      
      ac21  = aloc21(:)*detjac(ie);
      ac22  = aloc22(:)*detjac(ie);
      ac23  = aloc23(:)*detjac(ie);
      ac24  = aloc24(:)*detjac(ie);
      
      ac31  = aloc31(:)*detjac(ie);
      ac32  = aloc32(:)*detjac(ie);
      ac33  = aloc33(:)*detjac(ie);
      ac34  = aloc34(:)*detjac(ie);
      
      ac41  = aloc41(:)*detjac(ie);
      ac42  = aloc42(:)*detjac(ie);
      ac43  = aloc43(:)*detjac(ie);
      ac44  = aloc44(:)*detjac(ie);
      
      rowdG(i_all)  = [rr rr rr rr rr+nov rr+nov rr+nov rr+nov rr+2*nov rr+2*nov rr+2*nov rr+2*nov rr+3*nov rr+3*nov rr+3*nov rr+3*nov];
      coldG(i_all)  = [tt tt+nov tt+2*nov tt+3*nov tt tt+nov tt+2*nov tt+3*nov tt tt+nov tt+2*nov tt+3*nov tt tt+nov tt+2*nov tt+3*nov];
      dG(i_all)     = [ac11; ac12; ac13; ac14; ac21; ac22; ac23; ac24; ac31; ac32; ac33; ac34; ac41; ac42; ac43; ac44];
      
      dof_ie        = elements(1:nln,ie);
      rowG(ii)      = [dof_ie; nov+dof_ie; 2*nov+dof_ie; 3*nov+dof_ie];
      
      
      resG(ii)      = res_SUPG*detjac(ie);
      
      i_all         = i_all + n_blocks2*nln2;
      iii           = iii   + nln2;
      ii            = ii    + n_blocks*nln;
     
end


end



