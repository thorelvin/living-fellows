# SPDX-License-Identifier: MIT
"""Analyze native Phase 0 recordings; requires NumPy and SciPy.

Fit circle radii after ten seconds, read actual speeds/angles, and fit a
body-origin radius model on right turns. Check it on left turns and by
omitting each target speed in turn. This is evidence analysis, not game code.
"""
import argparse, csv, json, math
from pathlib import Path
import numpy as np
from scipy.optimize import least_squares, minimize_scalar

def geometry(path):
    cars={}
    for row in csv.reader(path.open(),delimiter='\t'):
        if len(row)<3 or row[0]=='script':continue
        car=cars.setdefault(row[0],{'wheels':[]})
        if row[1]=='body':
            car.update(body=list(map(float,row[2].split(','))),scale=float(row[4]),
                       max_speed=float(row[6]),clamp_min=float(row[8]))
        elif row[1]=='wheel':
            car['wheels'].append(dict(index=int(row[2]),id=row[3],front=row[5]=='true',offset=list(map(float,row[7].split(',')))))
    for car in cars.values():
        front=np.mean([w['offset'][2] for w in car['wheels'] if w['front']])
        rear=np.mean([w['offset'][2] for w in car['wheels'] if not w['front']])
        car.update(wheelbase=abs(front-rear),front_z=front,rear_z=rear,
                   body_fraction=abs(front-rear)/car['body'][2])
    return cars

def fit_circle(points):
    p=points-points.mean(axis=0)
    start=np.linalg.lstsq(np.column_stack([2*p[:,0],2*p[:,1],np.ones(len(p))]),(p*p).sum(axis=1),rcond=None)[0]
    result=least_squares(lambda c:np.linalg.norm(p-c,axis=1)-np.linalg.norm(p-c,axis=1).mean(),start[:2])
    distances=np.linalg.norm(p-result.x,axis=1)
    return float(distances.mean()),float(np.sqrt(np.mean((distances-distances.mean())**2))),result.x+points.mean(axis=0)

def analyze(root):
    cars=geometry(root/'phase0-geometry-tsv.txt')
    rows=list(csv.DictReader((root/'phase0-tracks-csv.txt').open()))
    for row in rows:
        for key,value in list(row.items()):
            try:row[key]=float(value)
            except (ValueError,TypeError):pass
    completions={};steps={};response_steps=[]
    for row in csv.reader((root/'phase0-trials-tsv.txt').open(),delimiter='\t'):
        if len(row)<3:continue
        if row[1]=='complete':completions[row[0]]=float(row[2])
        if row[1]=='input_step':steps[row[0]]=float(row[2])*1000
        if row[1] in ('response_step_down','response_step_up'):
            response_steps.append((int(row[0]),row[1],float(row[2])*1000,float(row[4])))
    summary=[]
    for trial in sorted({int(r['trial']) for r in rows if r['mode']=='circle'}):
        track=[r for r in rows if r['mode']=='circle' and r['trial']==trial]
        car=cars[track[0]['script']]
        step=steps.get(str(trial),0)
        steady=[r for r in track if r['ms']>step+10000]
        if len(steady)<30:continue
        p=np.array([[r['x'],r['y']] for r in steady]);f=np.array([[r['fx'],r['fy']] for r in steady])
        sign=1 if car['front_z']>car['rear_z'] else -1
        rear=p+f*car['rear_z']*sign
        radius,rms,centre=fit_circle(p);rear_radius,rear_rms,_=fit_circle(rear)
        speed=float(np.median([abs(r['speed_kmh']) for r in steady]))
        delta=float(np.median([abs(r['controller_angle']) for r in steady]))
        wheel=float(np.median([r['wheel_angle'] for r in steady]))
        signed_input=float(np.median([r['input'] for r in steady]))
        command=abs(signed_input);clamp=float(np.median([r['clamp'] for r in steady]))
        predicted=car['wheelbase']/math.tan(min(command,clamp))
        heading=np.unwrap(np.arctan2(f[:,1],f[:,0]))
        rotation=abs(float(heading[-1]-heading[0]))
        icr_forward=np.sum((centre-p)*f,axis=1)
        beta=float(np.median(np.arcsin(np.clip(-icr_forward/radius,-1,1))))
        effective_delta=math.atan(car['wheelbase']/rear_radius)
        # Fit initial native response, before clamping. No made-up wheel angles.
        ease=[r for r in track if step<=r['ms']<step+1800 and abs(r['controller_angle'])<min(command,r['clamp'])*.95]
        tau=float('nan');ease_rmse=float('nan')
        if len(ease)>=4:
            ts=np.array([(r['ms']-step)/1000 for r in ease]);ys=np.array([abs(r['controller_angle']) for r in ease])
            objective=lambda t:float(np.mean((command*(1-np.exp(-ts/t))-ys)**2))
            opt=minimize_scalar(objective,bounds=(.01,2),method='bounded')
            tau=float(opt.x);ease_rmse=math.sqrt(opt.fun)
        summary.append(dict(trial=trial,script=track[0]['script'],cruise=track[0]['cruise_kmh'],input=signed_input,
            completed=str(trial) in completions,samples=len(steady),seconds=(steady[-1]['ms']-steady[0]['ms'])/1000,
            radians=rotation,actual_kmh=speed,controller_rad=delta,wheel_rad=wheel,clamp=clamp,wheelbase=car['wheelbase'],
            centre_radius=radius,rear_radius=rear_radius,fit_rms=rms,rear_fit_rms=rear_rms,predicted_radius=predicted,
            icr_forward=float(np.median(icr_forward)),body_slip_degrees=math.degrees(beta),
            relative_error=rear_radius/predicted-1,effective_delta=effective_delta,angle_ratio=effective_delta/delta,
            tau=tau,ease_rmse=ease_rmse,min_skid=min(r['skid'] for r in steady if isinstance(r['skid'],float)),
            max_gap_ms=max(r['dt_ms'] for r in steady),surfaces=sorted(set(r['surface'] for r in steady)),
            damage_change=track[-1]['damage_sum']-track[0]['damage_sum'],health_min=min(r['health'] for r in track),
            zombie_kills=max(r['zombies_killed'] for r in track)))
        record=summary[-1]
        record['pose_speed_ratio']=(record['centre_radius']*record['radians']/record['seconds'])/(record['actual_kmh']/3.6)
        body=[r.get('body_condition_sum') for r in track]
        have_body=all(isinstance(v,float) for v in body)
        record['body_condition_change']=min(body)-body[0] if have_body else record['damage_change']
        record['wheel_controller_error']=max(abs(r['wheel_angle']-abs(r['controller_angle'])) for r in steady)
        record['controller_command_error']=max(abs(abs(r['controller_angle'])-min(abs(r['input']),r['clamp'])) for r in steady)
        record['quality_ok']=bool(record['completed'] and record['radians']>=2*math.pi
            and record['fit_rms']<.05 and record['max_gap_ms']<250
            and record['body_condition_change']==0 and record['health_min']==100
            and record['zombie_kills']==0 and record['wheel_controller_error']<.02
            and record['controller_command_error']<.02
            and record['surfaces']==['blends_street_01_0'])
    responses=[]
    for trial,phase,step,target_input in response_steps:
        track=[r for r in rows if r['trial']==trial]
        before=[r for r in track if r['ms']<=step]
        if not before:continue
        initial=abs(before[-1]['controller_angle']);target=abs(target_input)
        points=[r for r in track if r['mode']=='response' and step<r['ms']<step+1800
            and (target<initial or abs(r['controller_angle'])<r['clamp']-.01)]
        if len(points)<4:continue
        ts=np.array([(r['ms']-step)/1000 for r in points])
        ys=np.array([abs(r['controller_angle']) for r in points])
        objective=lambda tau:float(np.mean((target+(initial-target)*np.exp(-ts/tau)-ys)**2))
        opt=minimize_scalar(objective,bounds=(.01,2),method='bounded')
        kmh=float(np.median([abs(r['speed_kmh']) for r in points]));car=cars[track[0]['script']]
        nominal_tau=-1/(60*math.log(1-.06*max(.1,1-kmh/car['max_speed'])))
        responses.append(dict(trial=trial,phase=phase,actual_kmh=kmh,initial=initial,target=target,
            tau=float(opt.x),nominal_tau=nominal_tau,rmse=math.sqrt(opt.fun),samples=len(points)))
    result=dict(root=str(root),cars=cars,circles=summary,responses=responses,completed=completions)
    return result,rows


def fit(rows,cars):
    profiles={}
    for name,car in cars.items():
        points=[r for r in rows if r['script']==name and r['completed']]
        if any(not r.get('quality_ok',False) for r in points):
            raise ValueError('Completed circles failed quality checks: '+name)
        train=[r for r in points if r['input']>0]
        holdout=[r for r in points if r['input']<0]
        if len(train)!=6 or len(holdout)!=6:continue
        def features(r):
            return [1, math.tan(r['controller_rad'])**2, (r['actual_kmh']/3.6)**2]
        # Body-origin radius, rather than the rear-axle radius, is what the LF
        # follower measures. This gain includes slip and the origin's offset.
        x=np.array([features(r) for r in train])
        y=np.array([r['centre_radius']*math.tan(r['controller_rad'])/car['wheelbase'] for r in train])
        coeff=np.linalg.lstsq(x,y,rcond=None)[0]
        def error(r):
            predicted=car['wheelbase']/math.tan(r['controller_rad'])*float(np.array(features(r))@coeff)
            return dict(trial=r['trial'],predicted=predicted,measured=r['centre_radius'],relative_error=predicted/r['centre_radius']-1)
        left=[error(r) for r in holdout];right=[error(r) for r in train]
        # The velocity direction differs from the car's forward heading. Fit
        # longitudinal ICR offset as a function of speed for the scratch model.
        beta_x=np.array([features(r) for r in train])
        beta_y=np.array([-r['icr_forward'] for r in train])
        beta_coeff=np.linalg.lstsq(beta_x,beta_y,rcond=None)[0]
        cross_validation=[]
        for speed in sorted(set(r['cruise'] for r in train)):
            sample=[r for r in train if r['cruise']!=speed]
            test=[r for r in train if r['cruise']==speed]
            mx=np.array([features(r) for r in sample]);my=np.array([r['centre_radius']*math.tan(r['controller_rad'])/car['wheelbase'] for r in sample])
            mc=np.linalg.lstsq(mx,my,rcond=None)[0]
            for r in test:
                pred=car['wheelbase']/math.tan(r['controller_rad'])*float(np.array(features(r))@mc)
                cross_validation.append(dict(trial=r['trial'],omitted_speed=speed,relative_error=pred/r['centre_radius']-1))
        profiles[name]=dict(gain_coeff=coeff.tolist(),icr_offset_coeff=beta_coeff.tolist(),
            wheelbase=car['wheelbase'],max_speed=car['max_speed'],tau_median=float(np.median([r['tau'] for r in train])),
            train=right,holdout=left,max_train_error=max(abs(r['relative_error']) for r in right),
            speed_cross_validation=cross_validation,
            max_omitted_speed_error=max(abs(r['relative_error']) for r in cross_validation),
            max_holdout_error=max((abs(r['relative_error']) for r in left),default=0))
    return profiles


if __name__ == '__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('root',type=Path,help='Directory containing phase0-*.txt')
    ap.add_argument('--out',required=True,type=Path)
    args=ap.parse_args();result,_=analyze(args.root)
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/'analysis.json').write_text(json.dumps(result,indent=2,allow_nan=False))
    models=fit(result['circles'],result['cars'])
    (args.out/'mapping.json').write_text(json.dumps(models,indent=2,allow_nan=False))
    if result['circles']:
        with (args.out/'circles.csv').open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=result['circles'][0].keys())
            writer.writeheader();writer.writerows(result['circles'])
    print('Completed circles:',sum(r['completed'] for r in result['circles']))
    for name,model in models.items():
        print(name,'opposite-direction radius error %.2f%%; omitted-speed error %.2f%%' %
            (100*model['max_holdout_error'],100*model['max_omitted_speed_error']))
