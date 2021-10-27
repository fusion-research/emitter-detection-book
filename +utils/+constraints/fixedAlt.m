function [a, a_grad] = fixedAlt(alt, type)
%FIXEDALT Summary of this function goes here
%   Detailed explanation goes here

error('constraints must be rewritten for 2D position inputs (nDim x nPoints)');

if nargin < 2 || isempty(type)
    type='ellipse';
end

switch lower(type)
    case 'flat'
        a = @(x) x(2,:) - h;
        a_grad = @(x) [0,0,1]'*ones(1,size(x,2));
        
    case 'sphere'
        a = @(x) fixedAltConstraintSphere(x, alt);
        a_grad = @(x) fixedAltGradSphere(x);
        
    case 'ellipse'
        a = @(x) fixedAltConstraintEllipse(x, alt);
        a_grad = @(x) fixedAltGradSphere(x, alt);
        
    otherwise
        error('Invalid case type when calling fixedAlt; must be one of {flat|sphere|ellipse}.');
end


function [epsilon, scale] = fixedAltConstraintSphere(x, alt)
    % Implement equation 5.5, and the scale term defined in 5.9
    
    radius_tgt_sq = sum(abs(x).^2,1); % x'x
    epsilon = radius_tgt_sq - (utils.constants.radiusEarth + alt).^2; % eq 5.5
    scale = (utils.constants.radiusEarth + alt)/ sqrt(radius_tgt_sq); % eq 5.9, modified

end

function epsilon_grad = fixedAltGradSphere(x)

    epsilon_grad = x;

end

function [epsilon, scale] = fixedAltConstraintEllipse(x, alt)
    % Load constants
    e1sq = utils.constants.first_ecc_sq;
    
    % Compute geodetic latitude
    [lat, ~, ~] = utils.ecef2lla(x(1,:), x(2,:), x(3,:));
    
    % Compute effective radius
    eff_rad = utils.effRadiusEarth(lat);
    
    % Compute geodetic height (desired)
    ht_geod_desired = eff_rad + alt;
    
    % Compute Geocentric height (desired)
    ht_geoc_desired = (1-e1sq) * eff_rad + alt;
        
    % Loop over points
    tgt_rad_sq = zeros(1, size(x,2)); 
    for idx = 1:size(x,2)
        % Compute projection P
        P = diag([1, 1, ht_geod_desired(idx)^2 / ht_geoc_desired(idx)^2]);

        % Compute Projected Target Radius
        tgt_rad_sq(idx) = x(:,idx)'*P*x(:,idx);
    end
    
    epsilon = tgt_rad_sq - ht_geoc_desired.^2;
    
    % Compute scale
    scale = ht_geoc_desired./sqrt(tgt_rad_sq);
    
end        

function epsilon_grad = fixedAltGradEllipse(x, alt)
    % Load constants
    e1sq = utils.constants.first_ecc_sq;
    a = utils.constants.semimajor_axis_km * 1e3;
    Re = utils.constants.Re_true;
    
    % Compute geodetic latitude
    [lat, ~, ~] = utils.ecef2lla(x(1,:), x(2,:), x(3,:));
    lat_rad = lat*pi/180;
    
    % Compute effective radius
    eff_rad = utils.effRadiusEarth(lat_rad, false);
    
    % Compute geodetic height (desired)
    ht_geod_desired = eff_rad + alt;
    
    % Compute Geocentric height (desired)
    ht_geoc_desired = (1-e1sq) * eff_rad + alt;
    
    % Break position into x/y/z components
    xx = x(1,:);
    yy = x(2,:);
    zz = x(3,:);
    
    % Pre-compute some repeated terms
    xy_len_sq = xx.^2+yy.^2;
    xy_len = sqrt(xy_len_sq);
    zz_sq = zz.^2;
    
    sin_lat = sin(lat_rad);
    cos_lat = cos(lat_rad);
    
    % Compute gradient of geodetic latitude, equations 5.24-5.26
    dlat_dx = -xx.*zz*(1-e1sq) ./ (xy_len .* (zz.^2 + (1-e1sq)^2 * xy_len_sq));
    dlat_dy = -yy.*zz*(1-e1sq) ./ (xy_len .* (zz.^2 + (1-e1sq)^2 * xy_len_sq));
    dlat_dz = (1-e1sq)*xy_len ./ (zz_sq + (1-e1sq)*xy_len_sq);

    % Compute gradient of effective radius, equations 5.21-5.23
    dR_dx = a*e1sq*sin_lat.*cos_lat.*dlat_dx./(1-e1sq*sin_lat.^2).^(1.5);
    dR_dy = a*e1sq*sin_lat.*cos_lat.*dlat_dy./(1-e1sq*sin_lat.^2).^(1.5);
    dR_dz = a*e1sq*sin_lat.*cos_lat.*dlat_dz./(1-e1sq*sin_lat.^2).^(1.5);
    
    % Compute gradient of constraint (epsilon), equations 5.18-5.20
    de_dx = 2*xx + 2*ht_geoc_desired.*dR_dx.*(zz_sq*((ht_geod_desired-ht_geoc_desired*(1-e1sq))./ht_geod_desired.^3)-1);
    de_dy = 2*yy + 2*ht_geoc_desired.*dR_dy.*(zz_sq*((ht_geod_desired-ht_geoc_desired*(1-e1sq))./ht_geod_desired.^3)-1);
    de_dz = 2*zz.*ht_geoc_desired./ht_geod_desired+2*ht_geoc_desired.*dR_dz.*(zz_sq*(ht_geod_desired-ht_geoc_desired*(1-e1sq))./ht_geod_desired.^3);

    epsilon_grad = [de_dx; de_dy; de_dz];
    
end

end