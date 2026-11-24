// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.util.Locale;

/** Geometry and closed-loop checks use an analytic lane reference independent of the builder. */
public final class SCIntersectionTurnsTest {
    private static int checks;
    private static void require(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    record V(double x, double y) {
        V add(V q) { return new V(x + q.x, y + q.y); }
        V sub(V q) { return new V(x - q.x, y - q.y); }
        V mul(double n) { return new V(x * n, y * n); }
        V right() { return new V(-y, x); }
        double dot(V q) { return x * q.x + y * q.y; }
        double cross(V q) { return x * q.y - y * q.x; }
        double norm() { return Math.hypot(x, y); }
    }
    record Vehicle(String name, SCDrivePath.CornerProfile profile,
                   double g0, double ga, double gv, double e0, double ea, double ev) { }
    // 42.22.2 Phase 0 native fits, with the same extrapolation used in its scratch model.
    static final Vehicle[] VEHICLES = {
        new Vehicle("sedan", new SCDrivePath.CornerProfile(true, .809991f, 2.370004f, 2.65993f, 90, .3f, 6),
                .940947862, .249484735, .003391828, 1.118584770, .019201190, -.003806027),
        new Vehicle("van", new SCDrivePath.CornerProfile(true, .850031f, 2.120027f, 2.560012f, 65, .3f, 6),
                .932745624, .265695493, .004024477, .983831394, .016130457, -.003954096),
        new Vehicle("pickup", new SCDrivePath.CornerProfile(true, .789971f, 1.989988f, 2.449902f, 70, .3f, 6),
                .938321331, .246610224, .003254757, 1.070310123, .039106406, -.004049858)
    };
    static class World implements SCLaneScan.World {
        long queries;
        int kind(int x, int y) { return SCLaneScan.CLEAR; }
        @Override public int squareKind(int x, int y, int z) { queries++; return kind(x, y); }
        @Override public boolean edgeBlocked(int fx, int fy, int tx, int ty, int z) { return false; }
    }
    static final class Car {
        final Vehicle vehicle;
        final boolean nativeModel;
        double x, y, heading, speed, wheel;
        Car(V point, double heading, Vehicle vehicle, boolean nativeModel) {
            x = point.x; y = point.y; this.heading = heading; this.vehicle = vehicle; this.nativeModel = nativeModel;
        }
        void step(SCDriveControl.Input input, double dt) {
            if (nativeModel) {
                if (Math.abs(input.steering()) > .1) {
                    double tick = .06 * Math.max(.1, 1 - Math.abs(speed * 3.6) / vehicle.profile.maxSpeed());
                    wheel += (input.steering() - wheel) * (1 - Math.pow(1 - tick, 60 * dt));
                } else wheel = Math.abs(wheel) <= .04 ? 0 : Math.copySign(Math.max(0, Math.abs(wheel) - 2.4 * dt), wheel);
                double cap = .3 + .6 * (1 - Math.min(1, Math.abs(speed * 3.6) / vehicle.profile.maxSpeed()));
                wheel = Math.max(-cap, Math.min(cap, wheel));
            } else {
                double target = input.steering() * Math.toRadians(32);
                wheel += Math.max(-Math.PI / 2 * dt, Math.min(Math.PI / 2 * dt, target - wheel));
            }
            if (input.brake()) speed = approach(speed, 6 * dt);
            else if (input.forward()) speed = speed < -.1 ? approach(speed, 6 * dt) : speed + 2.5 * dt;
            else if (input.backward()) speed = speed > .1 ? approach(speed, 6 * dt) : speed - 2 * dt;
            else speed = approach(speed, dt);
            speed = Math.max(-6 / 3.6, Math.min(60 / 3.6, speed));
            double yaw, beta = 0;
            if (nativeModel && Math.abs(wheel) > 1e-5) {
                double tangent = Math.abs(Math.tan(wheel));
                double half = Math.tan(.5);
                double gain = vehicle.g0 + vehicle.ga * tangent * tangent + vehicle.gv * speed * speed;
                if (tangent < half) gain = 1 + (Math.max(1, vehicle.g0 + vehicle.ga * half * half
                        + vehicle.gv * speed * speed) - 1) * Math.pow(tangent / half, 2);
                double radius = vehicle.profile.wheelbase() / tangent * Math.max(1, gain);
                yaw = Math.signum(wheel) * speed / radius * dt;
                double offset = Math.max(0, vehicle.e0 + vehicle.ea * tangent * tangent + vehicle.ev * speed * speed);
                beta = Math.copySign(Math.asin(Math.min(.9, offset / radius)), wheel);
            } else yaw = speed / 2.7 * Math.tan(wheel) * dt;
            double movement = heading + (nativeModel ? beta + yaw / 2 : yaw);
            x += speed * Math.cos(movement) * dt; y += speed * Math.sin(movement) * dt;
            heading += yaw;
        }
        private static double approach(double n, double step) { return Math.copySign(Math.max(0, Math.abs(n) - step), n); }
    }
    private static V intersect(V p, V a, V q, V b) { return p.add(a.mul(q.sub(p).cross(b) / a.cross(b))); }
    private static double lane(double w) { return w >= 6 ? w / 4 : 0; }
    private static double segmentDistance(V p, V a, V b) {
        V d = b.sub(a); double t = Math.max(0, Math.min(1, p.sub(a).dot(d) / d.dot(d)));
        return p.sub(a.add(d.mul(t))).norm();
    }
    static final class Reference {
        final V a, b, start, finish, laneCorner, arcStart, arcEnd, center;
        final double angle, radius, inWidth, outWidth;
        Reference(double angle, double rotation, double inWidth, double outWidth, Vehicle vehicle) {
            this.angle = angle;
            this.inWidth = inWidth; this.outWidth = outWidth;
            a = new V(Math.cos(rotation), Math.sin(rotation));
            b = new V(Math.cos(rotation + angle), Math.sin(rotation + angle));
            V origin = new V(200, 200);
            start = origin.sub(a.mul(70)).add(a.right().mul(lane(inWidth)));
            finish = origin.add(b.mul(70)).add(b.right().mul(lane(outWidth)));
            laneCorner = intersect(origin.add(a.right().mul(lane(inWidth))), a,
                    origin.add(b.right().mul(lane(outWidth))), b);
            double min = vehicle.profile.minimumRadius();
            double preferred;
            if (angle > 0) {
                V kerb = intersect(origin.add(a.right().mul(inWidth / 2)), a,
                        origin.add(b.right().mul(outWidth / 2)), b);
                // Independent numerical search for the largest kerb-safe circle.
                double largest = 0;
                for (double r = .5; r <= 20; r += .005) {
                    V c = laneCorner.sub(a.mul(r * Math.tan(angle / 2))).add(a.right().mul(r));
                    if (r - c.sub(kerb).norm() >= vehicle.profile.halfWidth() + .3) largest = r;
                }
                preferred = Math.max(min, Math.min(Math.min(inWidth, outWidth) / 2, largest));
            } else preferred = Math.max(min, outWidth / 2 + lane(inWidth));
            double shiftIn = laneCorner.sub(origin.add(a.right().mul(lane(inWidth)))).dot(a);
            double shiftOut = laneCorner.sub(origin.add(b.right().mul(lane(outWidth)))).dot(b);
            double tangent = Math.max(preferred * Math.tan(Math.abs(angle) / 2), Math.max(shiftIn, -shiftOut));
            radius = tangent / Math.tan(Math.abs(angle) / 2);
            arcStart = laneCorner.sub(a.mul(tangent)); arcEnd = laneCorner.add(b.mul(tangent));
            center = arcStart.add(a.right().mul(Math.signum(angle) * radius));
        }
        double distance(V p) {
            double best = Math.min(segmentDistance(p, start, arcStart), segmentDistance(p, arcEnd, finish));
            V u = arcStart.sub(center), v = p.sub(center);
            double turn = Math.atan2(u.cross(v), u.dot(v));
            if (Math.signum(angle) * turn >= 0 && Math.abs(turn) <= Math.abs(angle)) best = Math.min(best, Math.abs(v.norm() - radius));
            return Math.min(best, Math.min(p.sub(arcStart).norm(), p.sub(arcEnd).norm()));
        }
    }
    private static SCDrivePath source(Reference r, float inWidth, float outWidth) {
        V p = new V(200, 200), first = p.sub(r.a.mul(70)), last = p.add(r.b.mul(70));
        return SCDrivePath.parse(String.format(Locale.ROOT, "%.6f,%.6f,%.2f;200,200,%.2f;%.6f,%.6f,%.2f",
                first.x, first.y, inWidth, inWidth, last.x, last.y, outWidth));
    }

    record Result(double error, double seconds, double cornerSpeed, double startDelay,
                  int sideViolations, int projectionSkip, long scans, int fallbacks, SCRoadFollower.Mode mode) { }

    private static SCDriveControl.Input controls(Car car, SCRoadFollower.Command command, float front, float rear) {
        float speed=(float)(car.speed*3.6);
        float gap=command.maneuver?SCDriveControl.MANEUVER_GAP_TILES:SCDriveControl.HOLD_GAP_TILES;
        return command.targetKmh<0?SCDriveControl.reverse(speed,-command.targetKmh,command.steering,rear)
                :command.cornerSpeed?SCDriveControl.corner(speed,command.targetKmh,command.steering,front,gap)
                :SCDriveControl.cruise(speed,command.targetKmh,command.steering,front,gap);
    }

    private static Result drive(Reference reference, SCDrivePath path, Vehicle vehicle,
                                boolean nativeModel, float scale, boolean plain) {
        SCRoadFollower follower = new SCRoadFollower(path, scale > 1 ? 50 : 30, true, false, scale);
        double heading = Math.atan2(reference.a.y, reference.a.x);
        Car car = new Car(reference.start.add(reference.a.mul(4)), heading, vehicle, nativeModel);
        World world = new World();
        SCRoadFollower.Command command = new SCRoadFollower.Command();
        double error = 0, cornerSpeed = 0, delay = Double.NaN;
        boolean entered = false, exited = false;
        int wrongSide = 0, maxSkip = 0, previousSegment = -1;
        long now = 0;
        SCDrivePath.Projection projection = new SCDrivePath.Projection();
        for (int frame = 0; frame < 4500 && follower.mode() != SCRoadFollower.Mode.ARRIVED; frame++) {
            follower.update(world, (float) car.x, (float) car.y, 0, (float) Math.cos(car.heading),
                    (float) Math.sin(car.heading), (float) (car.speed * 3.6),
                    vehicle.profile.halfWidth(), vehicle.profile.halfLength(), -1, -1, now, command);
            V position = new V(car.x, car.y), relative = position.sub(new V(200, 200));
            if (position.sub(reference.arcStart).dot(reference.a) >= 0) entered = true;
            double headingError = Math.abs(SCTurnAround.wrap((float) (car.heading
                    - Math.atan2(reference.b.y, reference.b.x))));
            if (entered && position.sub(reference.arcEnd).dot(reference.b) > 0 && headingError < Math.toRadians(15)) exited = true;
            if (entered && !exited) cornerSpeed = Math.max(cornerSpeed, Math.abs(car.speed * 3.6));
            if (Double.isNaN(delay) && Math.abs(SCTurnAround.wrap((float) (car.heading - heading))) > .08) {
                delay = position.sub(reference.arcStart).dot(reference.a);
            }
            if (reference.angle > 0 && relative.norm() > 6
                    && (reference.inWidth >= 6 && relative.dot(reference.a.right()) < -.02
                        || reference.outWidth >= 6 && relative.dot(reference.b.right()) < -.02)) wrongSide++;
            if (reference.angle < 0 && entered && reference.outWidth >= 6
                    && position.sub(reference.arcEnd).dot(reference.b) > 3
                    && relative.dot(reference.b.right()) < -.02) wrongSide++;
            path.project((float) car.x, (float) car.y, previousSegment, projection);
            if (previousSegment >= 0) maxSkip = Math.max(maxSkip, projection.segment - previousSegment);
            previousSegment = projection.segment;
            SCDriveControl.Input input = controls(car,command,-1,-1);
            if(Boolean.getBoolean("turnTrace")&&frame%10==0) System.out.printf(Locale.ROOT,
                    "TURN_DYNAMIC f=%d pos=%.3f,%.3f heading=%.2f speed=%.2f target=%.2f steer=%.3f along=%.3f seg=%d%n",
                    frame,car.x,car.y,Math.toDegrees(car.heading),car.speed*3.6,command.targetKmh,command.steering,
                    projection.along,projection.segment);
            car.step(input, 1.0 / 30); now += 33;
            error = Math.max(error, reference.distance(new V(car.x, car.y)));
        }
        return new Result(error, now / 1000.0, cornerSpeed, delay, wrongSide, maxSkip, world.queries,
                follower.cornerFallbacks(), follower.mode());
    }

    private static void matrix(boolean enforceTiming) {
        java.util.ArrayList<String> failures = new java.util.ArrayList<>();
        java.util.ArrayList<String> metrics = new java.util.ArrayList<>();
        metrics.add("vehicle,scale,inWidth,outWidth,angle,rotation,sharp,reason,radius,error,speed,delay,timeRatio,wrongSide");
        int runs = 0, sharp = 0, slow = 0, wideLeft = 0;
        double maxRight = 0, maxLeft = 0, maxTimeRatio = 0;
        for (Vehicle base : VEHICLES) for (int scale : new int[] {1, 2}) {
            SCDrivePath.CornerProfile p = base.profile;
            Vehicle vehicle = new Vehicle(base.name, new SCDrivePath.CornerProfile(true, p.halfWidth(), p.halfLength(),
                    p.wheelbase(), p.maxSpeed(), p.steeringClamp(), 6 * scale), base.g0, base.ga, base.gv, base.e0, base.ea, base.ev);
            for (float[] widths : new float[][] {{6,6},{8,8},{12,12},{12,8},{8,12},{8,5},{5,8}})
                for (int degrees : new int[] {30,45,60,90,120,135}) for (int side : new int[] {1,-1})
                    for (int rotation : new int[] {0,90,180,270,30}) {
                        Reference reference = new Reference(Math.toRadians(side * degrees), Math.toRadians(rotation), widths[0], widths[1], vehicle);
                        SCDrivePath raw = source(reference, widths[0], widths[1]);
                        SCDrivePath path = raw.withCorners(vehicle.profile);
                        String name = vehicle.name + " scale=" + scale + " w=" + widths[0] + ">" + widths[1]
                                + " angle=" + side*degrees + " rotation=" + rotation;
                        if(System.getProperty("turnScenario")!=null&&!name.equals(System.getProperty("turnScenario"))) continue;
                        require(path.x(0) == raw.x(0) && path.y(0) == raw.y(0)
                                && path.x(path.points()-1) == raw.x(raw.points()-1) && path.y(path.points()-1) == raw.y(raw.points()-1),
                                "route endpoints stay exact: " + name);
                        if (path.cornersSharp() > 0) sharp++;
                        for (boolean nativeModel : new boolean[] {true,false}) {
                            Result result = drive(reference, path, vehicle, nativeModel, scale, false);
                            runs++;
                            if (result.mode != SCRoadFollower.Mode.ARRIVED) failures.add(name + " native=" + nativeModel + " never arrived");
                            if (result.fallbacks != 0) failures.add(name + " native=" + nativeModel + " open-world fallback=" + result.fallbacks);
                            if (!nativeModel) continue;
                            double limit = side > 0 ? 1 : 1.5;
                            if (side > 0) maxRight = Math.max(maxRight, result.error); else maxLeft = Math.max(maxLeft, result.error);
                            if (result.error > limit + .02) failures.add(name + " lane=" + result.error + " sharp=" + path.cornersSharp());
                            if (result.cornerSpeed > 6*scale+1.01) failures.add(name + " cornerSpeed=" + result.cornerSpeed);
                            if (!Double.isFinite(result.startDelay) || result.startDelay > 2.01)
                                failures.add(name + " steeringDelay=" + result.startDelay);
                            if (result.sideViolations > 0) failures.add(name + " wrongSide=" + result.sideViolations);
                            if (result.projectionSkip > 6) failures.add(name + " projectionSkip=" + result.projectionSkip);
                            Result old = drive(reference, raw, vehicle, true, scale, true);
                            double ratio = result.seconds / old.seconds;
                            SCDrivePath.Corner c = path.corner(0);
                            metrics.add(String.format(Locale.ROOT, "%s,%d,%.0f,%.0f,%d,%d,%d,%s,%.4f,%.5f,%.4f,%.4f,%.5f,%d",
                                    vehicle.name, scale, widths[0], widths[1], side*degrees, rotation, path.cornersSharp(),
                                    c.sharpReason(), c.radius(), result.error, result.cornerSpeed, result.startDelay, ratio, result.sideViolations));
                            maxTimeRatio = Math.max(maxTimeRatio, ratio);
                            // User approved 20% only for the remaining thirty
                            // normal-speed 135-degree left cases into 12 m roads.
                            boolean wideLeftAllowance=scale==1&&side<0&&degrees==135
                                    &&widths[1]==12&&(widths[0]==8||widths[0]==12);
                            if(wideLeftAllowance) wideLeft++;
                            double timeBudget=wideLeftAllowance?1.20:1.15;
                            if (ratio > timeBudget+0.001) {
                                slow++;
                                if(enforceTiming) failures.add(name + " tripTime=" + ratio);
                            }
                        }
                    }
        }
        System.out.printf(Locale.ROOT, "TURN_MATRIX runs=%d sharp=%d right=%.3f left=%.3f timeRatio=%.3f failures=%d%n",
                runs, sharp, maxRight, maxLeft, maxTimeRatio, failures.size());
        require(System.getProperty("turnScenario")!=null||wideLeft==30,"twenty-percent allowance covers exactly thirty cases");
        System.out.printf(Locale.ROOT,"TURN_TIMING aboveBudget=%d limit=1.15 wideLeftLimit=1.20 wideLeftCases=%d worst=%.5f enforced=%s%n",
                slow,wideLeft,maxTimeRatio,enforceTiming);
        for (int i = 0; i < Math.min(80, failures.size()); i++) System.out.println("TURN_FAILURE " + failures.get(i));
        if (System.getProperty("turnReportDir") != null) {
            try {
                java.nio.file.Path dir = java.nio.file.Path.of(System.getProperty("turnReportDir"));
                java.nio.file.Files.createDirectories(dir);
                java.nio.file.Files.write(dir.resolve("matrix.csv"), metrics);
                java.nio.file.Files.write(dir.resolve("failures.txt"), failures);
            } catch (java.io.IOException failed) { throw new AssertionError(failed); }
        }
        require(failures.isEmpty(), "turn matrix failures=" + failures.size());
    }

    private static void smokeMatrix() {
        for (Vehicle vehicle : VEHICLES) for (int side : new int[] {1, -1}) {
            Reference reference = new Reference(side * Math.PI / 2, 0, 8, 8, vehicle);
            SCDrivePath path = source(reference, 8, 8).withCorners(vehicle.profile);
            require(path.corners() == 1 && path.corner(0).arc(), "single 90-degree turn rounds: " + vehicle.name + " " + side);
            for (boolean nativeModel : new boolean[] {true, false}) {
                SCRoadFollower follower = new SCRoadFollower(path, 30, true);
                Car car = new Car(reference.start.add(reference.a.mul(4)), 0, vehicle, nativeModel);
                World world = new World();
                SCRoadFollower.Command command = new SCRoadFollower.Command();
                double error = 0; long now = 0;
                for (int frame = 0; frame < 4500 && follower.mode() != SCRoadFollower.Mode.ARRIVED; frame++) {
                    follower.update(world, (float) car.x, (float) car.y, 0, (float) Math.cos(car.heading),
                            (float) Math.sin(car.heading), (float) (car.speed * 3.6),
                            vehicle.profile.halfWidth(), vehicle.profile.halfLength(), -1, -1, now, command);
                    SCDriveControl.Input input = controls(car,command,-1,-1);
                    car.step(input, 1.0 / 30); now += 33;
                    error = Math.max(error, reference.distance(new V(car.x, car.y)));
                }
                System.out.printf(Locale.ROOT, "TURN_SMOKE %s side=%d native=%s sharp=%d error=%.3f mode=%s seconds=%.2f scans=%d%n",
                        vehicle.name, side, nativeModel, path.cornersSharp(), error, follower.mode(), now / 1000.0, world.queries);
                require(follower.mode() == SCRoadFollower.Mode.ARRIVED, "rounded turn arrives");
                if (nativeModel) require(error <= (side > 0 ? 1 : 1.5), "independent lane error: " + error);
            }
        }
    }

    private static void geometry() {
        Vehicle vehicle = VEHICLES[0];
        for (int rotation : new int[] {0,30,90,180,270}) for (int angle : new int[] {30,45,60,90,120,135})
            for (int sign : new int[] {1,-1}) for (float width : new float[] {6,8,12}) {
                Reference reference = new Reference(Math.toRadians(sign*angle),Math.toRadians(rotation),width,width,vehicle);
                SCDrivePath root = source(reference,width,width), rounded=root.withCorners(vehicle.profile);
                require(rounded.corners()==1 && rounded.corner(0).arc(),"ordinary corner fits");
                SCDrivePath.Corner c=rounded.corner(0);
                require(Math.abs(c.angle()-Math.toRadians(sign*angle))<Math.toRadians(.01),"total corner angle");
                for(int i=1;i<rounded.points();i++) {
                    require(Math.hypot(rounded.x(i)-rounded.x(i-1),rounded.y(i)-rounded.y(i-1))>=.248,
                            "derived vertex spacing");
                }
                float[] point=new float[5];
                for(float at=c.start();at<=c.end();at+=.15f) {
                    rounded.pointAt(at,rounded.laneOffsetAt(at),point);
                    require(reference.distance(new V(point[0],point[1]))<.06,"analytic arc invariant");
                }
                SCDrivePath backwards=root.reversed().withCorners(vehicle.profile);
                require(backwards.corners()==1 && Math.signum(backwards.corner(0).angle())==-sign,
                        "reverse root changes turn side");
            }
        SCDrivePath root=SCDrivePath.parse("100,200,8;136,200,8;172,200,8;200,200,8;200,236,8;200,272,8");
        SCDrivePath path=root.withCorners(vehicle.profile);
        for(int original:new int[]{0,1,2,4,5}) {
            boolean found=false;
            for(int i=0;i<path.points();i++) if(Float.floatToIntBits(path.x(i))==Float.floatToIntBits(root.x(original))
                    && Float.floatToIntBits(path.y(i))==Float.floatToIntBits(root.y(original))
                    && path.width(i)==root.width(original)) found=true;
            require(found,"straight-stretch identity index="+original);
        }
        require(SCDrivePath.parse("100,200,8;170,200,8;240,200,8").withCorners(vehicle.profile).corners()==0,
                "straight route has no corner behaviour");
        require(SCDrivePath.parse("100,200,8;170,200,8;100,200,8").withCorners(vehicle.profile).corners()==0,
                "hairpin retains original behaviour");
        for(String text:new String[]{"100,200,8;106,200,8;106,270,8",
                "100,200,8;170,200,8;170,206,8","100,200,8;104,200,8;104,204,8"}) {
            SCDrivePath shortRoot=SCDrivePath.parse(text),shortPath=shortRoot.withCorners(vehicle.profile);
            require(shortPath.x(0)==shortRoot.x(0)&&shortPath.y(0)==shortRoot.y(0)
                    &&shortPath.x(shortPath.points()-1)==shortRoot.x(shortRoot.points()-1)
                    &&shortPath.y(shortPath.points()-1)==shortRoot.y(shortRoot.points()-1),"short-leg endpoint identity");
            for(int i=0;i<shortPath.corners();i++) if(shortPath.corner(i).arc()) {
                require(shortPath.corner(i).start()>=.99f
                        && shortPath.length()-shortPath.corner(i).end()>=2+vehicle.profile.halfLength()-.01,
                        "short-leg first/final straight reserves");
            }
        }
        SCDrivePath unknown=SCDrivePath.parse("100,200,0;200,200,0;200,300,0").withCorners(
                new SCDrivePath.CornerProfile(true,.95f,2.4f,Float.NaN,Float.NaN,Float.NaN,6));
        require(unknown.corners()==1&&Math.abs(unknown.corner(0).radius()-3)<1.1,"missing geometry has bounded fallback");
        StringBuilder many=new StringBuilder();
        double x=500,y=500,direction=0;
        for(int i=0;i<512;i++) {
            if(i>0) many.append(';');
            many.append(String.format(Locale.ROOT,"%.4f,%.4f,8",x,y));
            x+=Math.cos(direction)*15;y+=Math.sin(direction)*15;
            direction+=(i%2==0?1:-1)*Math.PI/2;
        }
        SCDrivePath bounded=SCDrivePath.parse(many.toString()).withCorners(vehicle.profile);
        require(bounded.points()<=SCDrivePath.MAX_CORNER_POINTS&&bounded.cornersSharp()>0,"bounded point budget falls back sharp");
        float previous=-1;
        for(int i=0;i<bounded.points();i++) {
            require(Float.isFinite(bounded.x(i))&&Float.isFinite(bounded.y(i)),"finite built coordinates");
            if(i>0) require(bounded.distance(i)>previous,"strictly ordered route distances");
            previous=bounded.distance(i);
        }
        sideFixture();
        System.out.println("TURN_GEOMETRY_PASS checks="+checks);
    }

    private static void sideFixture() {
        require(!SCCornerPathBuilder.sideSafe(198,198,200,200,1,0,0,1,(float)Math.PI/2,8,8,false),
                "V2 rejects off-side right-turn fixture");
        require(!SCCornerPathBuilder.sideSafe(180,180,200,200,1,0,0,-1,-(float)Math.PI/2,8,8,false),
                "V2 rejects off-side left-turn fixture");
        require(SCCornerPathBuilder.sideSafe(202,170,200,200,1,0,0,-1,-(float)Math.PI/2,8,8,true),
                "legal outgoing lane is not the incoming wrong side");
    }

    private static void sharpHold() {
        SCDrivePath path=SCDrivePath.parse("100,200,12;200,200,12;200,300,12")
                .withCorners(VEHICLES[0].profile).sharpCorner(0);
        SCRoadFollower follower=new SCRoadFollower(path,30,true);
        World world=new World();
        follower.update(world,194,203,0,1,0,6,.81f,2.37f,-1,-1,0,null);
        SCRoadFollower.Command command=follower.update(world,197,205,0,.7071068f,.7071068f,
                6,.81f,2.37f,-1,-1,200,null);
        require(command.targetKmh<=6,"mid-turn speed holds on switched-back corner");
        command=follower.update(world,197,215,0,0,1,6,.81f,2.37f,-1,-1,400,command);
        require(command.targetKmh>6,"aligned exit releases corner speed");
    }

    private static void reverse() {
        for(Vehicle vehicle:VEHICLES) {
            Reference reference=new Reference(Math.PI/2,0,12,8,vehicle);
            SCDrivePath root=source(reference,12,8),path=root.withCorners(vehicle.profile);
            SCRoadFollower follower=new SCRoadFollower(path,10,true);
            World world=new World();
            Car car=new Car(reference.finish,Math.PI/2,vehicle,true);
            follower.beginTurn((float)car.heading,1,true);
            SCRoadFollower.Command command=new SCRoadFollower.Command();
            long now=0;
            for(int i=0;i<1500&&follower.mode()==SCRoadFollower.Mode.TURNING;i++) {
                follower.update(world,(float)car.x,(float)car.y,0,(float)Math.cos(car.heading),(float)Math.sin(car.heading),
                        (float)(car.speed*3.6),vehicle.profile.halfWidth(),vehicle.profile.halfLength(),-1,-1,now,command);
                SCDriveControl.Input input=controls(car,command,-1,-1);
                car.step(input,1.0/30);now+=33;
            }
            require(follower.mode()==SCRoadFollower.Mode.FOLLOW,"physical turn-round completes: "+vehicle.name+" "+follower.mode());
            SCDrivePath back=follower.path();
            require(back.corners()==1&&back.corner(0).angle()<0,"reverse rebuild uses original route");
            require(back.original().x(0)==root.x(root.points()-1)&&back.original().y(0)==root.y(root.points()-1),
                    "reversed original endpoint");
            require(Math.abs(back.laneOffsetAt(back.corner(0).start())-2)<.01
                    &&Math.abs(back.laneOffsetAt(back.corner(0).end())-3)<.01,"reverse swaps actual road widths");
        }
        System.out.println("TURN_REVERSE_PASS");
    }

    private static void laneContract(boolean right) {
        for(Vehicle base:VEHICLES) for(int scale:new int[]{1,2}) for(float width:new float[]{6,8,12})
            for(int angle:new int[]{90,120,135}) {
                SCDrivePath.CornerProfile p=base.profile;
                Vehicle vehicle=new Vehicle(base.name,new SCDrivePath.CornerProfile(true,p.halfWidth(),p.halfLength(),
                        p.wheelbase(),p.maxSpeed(),p.steeringClamp(),6*scale),base.g0,base.ga,base.gv,base.e0,base.ea,base.ev);
                Reference reference=new Reference((right?1:-1)*Math.toRadians(angle),0,width,width,vehicle);
                SCDrivePath path=source(reference,width,width).withCorners(vehicle.profile);
                Result result=drive(reference,path,vehicle,true,scale,false);
                require(result.error<=(right?1:1.5),(right?"right":"left")+" lane error "+result.error
                        +" "+vehicle.name+" width="+width+" angle="+angle+" scale="+scale);
            }
    }

    private static void speedContract() {
        Vehicle vehicle=VEHICLES[0];
        Reference reference=new Reference(Math.PI/2,0,12,12,vehicle);
        Result result=drive(reference,source(reference,12,12).withCorners(vehicle.profile),vehicle,true,1,false);
        require(result.cornerSpeed<=7,"whole-corner speed limit "+result.cornerSpeed);
    }

    private static void speedGovernor() {
        Vehicle vehicle=VEHICLES[0];
        Car car=new Car(new V(130,200),0,vehicle,true);
        SCRoadFollower.Command command=new SCRoadFollower.Command();
        command.cornerSpeed=true;command.targetKmh=6;
        double total=0,peak=0;int count=0;
        for(int frame=0;frame<180;frame++) {
            car.step(controls(car,command,-1,-1),1.0/30);
            if(frame>=90) { total+=car.speed*3.6;peak=Math.max(peak,car.speed*3.6);count++; }
        }
        require(total/count>=5.8&&peak<=6.5,"corner governor holds requested speed mean="+total/count+" peak="+peak);
    }

    private static void approachTiming() {
        Vehicle vehicle=VEHICLES[2];
        Reference reference=new Reference(-Math.PI*.75,0,12,12,vehicle);
        SCDrivePath root=source(reference,12,12);
        Result rounded=drive(reference,root.withCorners(vehicle.profile),vehicle,true,1,false);
        Result baseline=drive(reference,root,vehicle,true,1,true);
        require(rounded.seconds/baseline.seconds<=1.20,"moving arc approach timing "+rounded.seconds/baseline.seconds);
    }

    private static void shortScan() throws ReflectiveOperationException {
        Vehicle vehicle=VEHICLES[0];
        Reference reference=new Reference(Math.PI/2,0,8,8,vehicle);
        SCDrivePath path=source(reference,8,8).withCorners(vehicle.profile);
        SCRoadFollower follower=new SCRoadFollower(path,30,true);
        World world=new World();
        follower.update(world,134,202,0,1,0,0,vehicle.profile.halfWidth(),vehicle.profile.halfLength(),-1,-1,0,null);
        // A real clipped end fragment is slightly over .001 along the encoded
        // line, but under .001 on its tighter physical lane. It must not turn
        // an everywhere-clear world into an unreadable-heading obstacle.
        float start=path.corner(0).end()-.0012f;
        java.lang.reflect.Method scan=SCRoadFollower.class.getDeclaredMethod("stripObstacle",SCLaneScan.World.class,
                int.class,float.class,float.class,float.class,float.class,float.class);
        scan.setAccessible(true);
        float hit=(float)scan.invoke(follower,world,0,start,path.laneOffsetAt(start),.5f,
                vehicle.profile.halfWidth(),vehicle.profile.halfLength());
        require(hit<0,"clipped arc scan stays clear: "+hit);
    }

    private static void merging() {
        Vehicle vehicle=VEHICLES[0];
        Reference reference=new Reference(Math.PI/2,0,8,8,vehicle);
        SCDrivePath path=source(reference,8,8).withCorners(vehicle.profile);
        float along=path.corner(0).start()+.01f;
        float[] pose=new float[5];
        path.pointAt(along,path.laneOffsetAt(along),pose);
        SCRoadFollower follower=new SCRoadFollower(path,30,true);
        follower.update(new World(),pose[0],pose[1],0,pose[2],pose[3],6,
                vehicle.profile.halfWidth(),vehicle.profile.halfLength(),-1,-1,0,null);
        System.out.println("TURN_MERGE_COST strips="+follower.stripScans());
        // Nine ten-degree pieces should combine into pairs, plus the exit.
        // Count actual strip traversals as well as cached square queries: a
        // shared cache otherwise conceals the cost of disabling F7.
        require(follower.stripScans()<=6,"merged arc scan cost "+follower.stripScans());
    }

    private static void filledStrip() throws ReflectiveOperationException {
        Vehicle vehicle=VEHICLES[0];
        World world=new World() {
            @Override int kind(int x,int y) {
                return x==7133&&y==8212?SCLaneScan.SOLID:SCLaneScan.CLEAR;
            }
        };
        // Actual barricade cell and sedan width from the retained native stop.
        // The original rays floor to columns 7132, 7134 and 7135, skipping 7133.
        require(!SCLaneScan.scan(world,7134,8220,0,0,-1,vehicle.profile.halfWidth(),0,10).blocked,
                "native strip alias fixture misses between legacy rays");
        SCDrivePath path=SCDrivePath.parse("7132.5,8220,6;7132.5,8200,6;7155,8200,6")
                .withCorners(vehicle.profile);
        SCRoadFollower follower=new SCRoadFollower(path,6,true);
        follower.update(world,7134,8220,0,0,-1,0,vehicle.profile.halfWidth(),
                vehicle.profile.halfLength(),-1,-1,0,null);
        java.lang.reflect.Method scan=SCRoadFollower.class.getDeclaredMethod("stripObstacle",SCLaneScan.World.class,
                int.class,float.class,float.class,float.class,float.class,float.class);
        scan.setAccessible(true);
        float hit=(float)scan.invoke(follower,world,0,0f,1.5f,10f,
                vehicle.profile.halfWidth(),vehicle.profile.halfLength());
        require(hit>=0&&hit<=8,"interior obstacle in corner route strip "+hit);
        SCLaneScan.Result swept=SCLaneScan.scanFilled(world,7134,8220,0,0,-1,
                2.31f,0,10,new java.util.HashMap<>());
        require(swept.blocked&&swept.hitX==7133&&swept.hitY==8212,
                "interior obstacle in widened corner body sweep");
    }

    private static void lateOffsetBodySweep() {
        Vehicle vehicle=VEHICLES[0];
        SCDrivePath path=SCDrivePath.parse("130,200,8;200,200,8;200,270,8").withCorners(vehicle.profile);
        World world=new World() {
            @Override int kind(int x,int y) {
                return x==194&&y==203?SCLaneScan.SOLID:SCLaneScan.CLEAR;
            }
        };
        // A sedan enters the turn at 6 km/h just three metres before a lamp.
        // The parallel passing strip is clear, but moving onto it this late
        // sweeps the rear of the real body across the lamp.
        Car car=new Car(new V(191,202),0,vehicle,true);
        car.speed=6.0/3.6;
        ObstacleResult result=obstacleDrive(path,vehicle,world,car);
        System.out.println("TURN_LATE_OFFSET "+result);
        require(result.collisions==0,"late offset avoids rear body collision "+result.collisions);
        require(result.mode==SCRoadFollower.Mode.ARRIVED,"late offset safely arrives "+result.mode);
    }

    record ObstacleResult(SCRoadFollower.Mode mode, int fallbacks, int reverseFrames, int collisions,
                          long queries, long strips, double seconds, double stoppedSpeed) { }

    private static ObstacleResult obstacleDrive(SCDrivePath path, Vehicle vehicle, World world) {
        return obstacleDrive(path,vehicle,world,null);
    }

    private static ObstacleResult obstacleDrive(SCDrivePath path, Vehicle vehicle, World world, Car initial) {
        SCRoadFollower follower = new SCRoadFollower(path, 30, true);
        float[] pose = new float[5];
        path.pointAt(4, path.cornerProfile() == null ? lane(path.width(0)) > 0 ? path.width(0)/4 : 0
                : path.laneOffsetAt(4), pose);
        Car car = initial==null?new Car(new V(pose[0],pose[1]), Math.atan2(pose[3],pose[2]), vehicle, true):initial;
        SCRoadFollower.Command command = new SCRoadFollower.Command();
        int collisions = 0, reverseFrames = 0;
        long now = 0, nextScan = 0;
        float front = -1, rear = -1;
        int frontKind=SCLaneScan.CLEAR;
        for (int frame=0;frame<6000;frame++) {
            float hx=(float)Math.cos(car.heading),hy=(float)Math.sin(car.heading);
            float hw=vehicle.profile.halfWidth(),hl=vehicle.profile.halfLength();
            if(now>=nextScan) {
                nextScan=now+100;
                SCLaneScan.Result ahead=SCLaneScan.scan(world,(float)car.x,(float)car.y,0,hx,hy,hw,hl+.1f,45);
                front=ahead.distance;frontKind=ahead.kind;
                rear=SCLaneScan.scan(world,(float)car.x,(float)car.y,0,-hx,-hy,hw,hl+.1f,8).distance;
            }
            follower.update(world,(float)car.x,(float)car.y,0,hx,hy,(float)(car.speed*3.6),
                    hw,hl,front,rear,frontKind,now,command);
            SCDriveControl.Input input=controls(car,command,front,rear);
            if(command.targetKmh<0) reverseFrames++;
            car.step(input,1.0/30);now+=33;
            for(int length=-2;length<=2;length++) for(int side=-1;side<=1;side++) {
                double px=car.x+Math.cos(car.heading)*hl*length/2-Math.sin(car.heading)*hw*side;
                double py=car.y+Math.sin(car.heading)*hl*length/2+Math.cos(car.heading)*hw*side;
                if(world.kind((int)Math.floor(px),(int)Math.floor(py))!=SCLaneScan.CLEAR) {
                    if(collisions==0&&Boolean.getBoolean("turnTrace")) System.out.printf(Locale.ROOT,
                            "TURN_COLLISION car=%.3f,%.3f heading=%.2f sample=%.3f,%.3f%n",car.x,car.y,
                            Math.toDegrees(car.heading),px,py);
                    collisions++;
                }
            }
            if(Boolean.getBoolean("turnTrace")&&frame%30==0) System.out.printf(Locale.ROOT,
                    "TURN_TRACE %.2f %.3f %.3f %.2f %.2f %s offsets=%.3f/%.3f falls=%d front=%.2f%n",
                    now/1000.0,car.x,car.y,Math.toDegrees(car.heading),car.speed*3.6,follower.mode(),
                    follower.offset(),follower.laneOffset(),follower.cornerFallbacks(),front);
            if(follower.mode()==SCRoadFollower.Mode.ARRIVED
                    ||follower.mode()==SCRoadFollower.Mode.BLOCKED&&Math.abs(car.speed)<.02&&now>8000) break;
        }
        return new ObstacleResult(follower.mode(),follower.cornerFallbacks(),reverseFrames,collisions,world.queries,
                follower.stripScans(),now/1000.0,car.speed*3.6);
    }

    private static World obstacleWorld(int kind) {
        return new World() {
            @Override int kind(int x,int y) {
                if(kind==0&&x>=194&&x<=195&&y>=202&&y<=205) return SCLaneScan.VEHICLE;
                if(kind==1&&x==196&&y==204) return SCLaneScan.SOLID;
                if(kind==2&&y>=221&&y<=224&&x>=188&&x<=212) return SCLaneScan.SOLID;
                // Solid pavement corners, retaining the existing two-metre shoulder.
                if(kind==3&&Math.abs(x+.5-200)>6&&Math.abs(y+.5-200)>6) return SCLaneScan.SOLID;
                return SCLaneScan.CLEAR;
            }
        };
    }

    private static void obstacles(String only) {
        for(Vehicle vehicle:VEHICLES) {
            Reference reference=new Reference(Math.PI/2,0,8,8,vehicle);
            SCDrivePath root=source(reference,8,8);
            String[] names={"wreck","lamp","blocked","walls"};
            for(int i=0;i<names.length;i++) {
                if(!only.equals("obstacles")&&!only.equals(names[i])&&!only.equals("cost")) continue;
                if(only.equals("cost")&&i!=0) continue;
                ObstacleResult result=obstacleDrive(root.withCorners(vehicle.profile),vehicle,obstacleWorld(i));
                System.out.println("TURN_OBSTACLE "+vehicle.name+" "+names[i]+" "+result);
                require(result.collisions==0,names[i]+" no body collision "+result.collisions);
                if(i==2) require(result.mode==SCRoadFollower.Mode.BLOCKED&&Math.abs(result.stoppedSpeed)<.1,
                        "fully blocked road stops");
                else require(result.mode==SCRoadFollower.Mode.ARRIVED,names[i]+" arrives "+result.mode);
                if(i==0) {
                    require(result.fallbacks==1,"wreck switches one corner back exactly once: "+result.fallbacks);
                    ObstacleResult old=obstacleDrive(root,vehicle,obstacleWorld(i));
                    System.out.println("TURN_SCAN_BASELINE "+old);
                    require(result.queries<=old.queries*2,"squareKind scan cost "+result.queries+" vs "+old.queries);
                    require(result.strips<=old.strips*2,"strip scan cost "+result.strips+" vs "+old.strips);
                }
            }
        }
    }

    private static void bumperCorner() {
        Vehicle vehicle=VEHICLES[0];
        Reference reference=new Reference(-Math.PI/2,0,6,6,vehicle);
        World world=new World() {
            @Override int kind(int x,int y) {
                // Real Home detour: the straight bumper ray sees the far
                // pavement while the legal left-turn body corridor is clear.
                return x>=204&&y<=193?SCLaneScan.SOLID:SCLaneScan.CLEAR;
            }
        };
        ObstacleResult result=obstacleDrive(source(reference,6,6).withCorners(vehicle.profile),vehicle,world);
        System.out.println("TURN_BUMPER "+result);
        require(result.mode==SCRoadFollower.Mode.ARRIVED,"bumper corner fallback arrives "+result.mode);
        require(result.collisions==0,"bumper corner fallback no body collision");
        require(result.fallbacks==1,"bumper corner fallback is one-way "+result.fallbacks);
    }

    private static void clearBumperLookAhead() {
        Vehicle vehicle=VEHICLES[0];
        for(boolean left:new boolean[]{false,true}) {
            SCDrivePath path=SCDrivePath.parse(left?"172,200,6;200,200,6;200,171,6"
                    :"228,200,6;200,200,6;200,171,6").withCorners(vehicle.profile);
            World world=new World() {
                @Override int kind(int x,int y) {
                    // Native Casey roadside fixtures at 7103,8311 and 7112,8313.
                    // Straight side rays see them 5.2 / 3.2 m beyond the bumper
                    // mid-turn; the actual curved car bodies never reach them.
                    return (left?x==205&&y==195:x==196&&y==193)?SCLaneScan.SOLID:SCLaneScan.CLEAR;
                }
            };
            ObstacleResult result=obstacleDrive(path,vehicle,world);
            System.out.println("TURN_CLEAR_BUMPER "+result);
            require(result.mode==SCRoadFollower.Mode.ARRIVED&&result.collisions==0,
                    "clear arc safely arrives beside distant lamp "+result);
            require(result.fallbacks==0,"clear arc does not sharpen for distant lamp "+result.fallbacks);
        }
    }

    private static void cornerBumperRecovery() {
        Vehicle vehicle=VEHICLES[0];
        Reference reference=new Reference(-Math.PI/2,0,6,6,vehicle);
        SCDrivePath root=source(reference,6,6);
        World world=new World() {
            @Override int kind(int x,int y) {
                return x>=191&&x<=194&&y==203?SCLaneScan.SOLID:SCLaneScan.CLEAR;
            }
        };
        // Recorded live pose, translated/rotated: 0.52 m off lane, six
        // degrees crooked and stopped before the checked arc starts.
        Car car=new Car(new V(186.33,202.02),Math.atan2(.1055,.9944),vehicle,true);
        ObstacleResult result=obstacleDrive(root.withCorners(vehicle.profile),vehicle,world,car);
        System.out.println("TURN_CORNER_RECOVERY "+result);
        require(result.mode==SCRoadFollower.Mode.ARRIVED,"corner bumper recovery arrives "+result.mode);
        require(result.collisions==0&&result.reverseFrames>0,"corner bumper recovery uses clear rear without contact");
        Car rawCar=new Car(new V(186.33,202.02),Math.atan2(.1055,.9944),vehicle,true);
        ObstacleResult raw=obstacleDrive(root,vehicle,world,rawCar);
        require(raw.mode!=SCRoadFollower.Mode.ARRIVED&&raw.reverseFrames==0,"raw-route bumper policy stays unchanged");
    }

    private static void rosewoodCornerRecovery() {
        Vehicle pickup = VEHICLES[2];
        // The parked vehicle occupies the outside of the turn from Main Street.
        SCDrivePath path = SCDrivePath.parse("8106,11732.484,8;8106,11774,8;8106,11777,6;8149.641,11777,6")
                .withCorners(pickup.profile);
        World world = new World() {
            @Override int kind(int x, int y) {
                return x >= 8105 && x <= 8107 && y >= 11779 && y <= 11784
                        ? SCLaneScan.VEHICLE : SCLaneScan.CLEAR;
            }
        };
        float halfWidth = pickup.profile.halfWidth(), halfLength = pickup.profile.halfLength();
        SCRoadFollower follower = new SCRoadFollower(path, 30, true);
        SCRoadFollower.Command command = new SCRoadFollower.Command();
        follower.update(world, 8103.719f, 11766.570f, 0, 0.011f, 1, 20, halfWidth, halfLength,
                12.4f, -1, SCLaneScan.VEHICLE, 0, command);
        for (long now : new long[]{ 300, 300 + SCRoadFollower.WEDGE_MS }) {
            follower.update(world, 8105.430f, 11774.312f, 0, 0.417f, 0.909f, 0, halfWidth, halfLength,
                    2.8f, -1, SCLaneScan.VEHICLE, now, command);
        }
        require(Math.abs(follower.offset() - follower.laneOffset()) > 0.5f,
                "Rosewood bumper recovery shares an active passing offset");
        require(follower.backingOff() && command.targetKmh < 0 && command.steering > 0.15f,
                "Rosewood reverse keeps turning left before trying forward again: steering=" + command.steering);

        follower = new SCRoadFollower(path, 30, true, false, 2);
        follower.update(world, 8108.203f, 11732.484f, 0, -0.089f, -0.996f, 0, halfWidth, halfLength,
                -1, -1, SCLaneScan.CLEAR, 0, command);
        require(follower.mode() == SCRoadFollower.Mode.TURNING && command.targetKmh == 8 && command.cornerSpeed,
                "the tuned police-station departure uses the doubled forward turn target");
    }

    private static void fixtures() throws java.io.IOException {
        Vehicle vehicle=VEHICLES[0];
        java.nio.file.Path file=java.nio.file.Path.of(System.getProperty("turnFixturePath",
                "tests/live/fixtures/intersection-phase0-42.22.2/junctions.tsv"));
        java.util.List<String> rows=java.nio.file.Files.readAllLines(file);
        require(rows.size()==5,"four measured map fixtures present");
        for(int i=1;i<rows.size();i++) {
            String[] row=rows.get(i).split("\\t"),points=row[5].split(";");
            StringBuilder source=new StringBuilder();
            for(String point:points) {
                String[] fields=point.split(",");
                if(source.length()>0) source.append(';');
                source.append(fields[0]).append(',').append(fields[1]).append(',').append(fields[2]);
            }
            SCDrivePath root=SCDrivePath.parse(source.toString());
            require(root!=null,"map fixture parses: "+row[0]);
            for(boolean reverse:new boolean[]{false,true}) {
                SCDrivePath original=reverse?root.reversed():root;
                SCDrivePath path=original.withCorners(vehicle.profile);
                require(path.corners()>0,"real fixture has checked corners: "+row[0]);
                require(path.x(0)==original.x(0)&&path.y(0)==original.y(0)
                        &&path.x(path.points()-1)==original.x(original.points()-1)
                        &&path.y(path.points()-1)==original.y(original.points()-1),"real fixture endpoints exact");
                float previous=0;
                for(int c=0;c<path.corners();c++) {
                    SCDrivePath.Corner corner=path.corner(c);
                    require(corner.start()>=previous&&corner.end()>=corner.start(),"map corners ordered");
                    previous=corner.end();
                    if(!corner.arc()) require(!corner.sharpReason().isEmpty(),"rejected corner names its invariant");
                    else {
                        float[] point=new float[5];
                        for(float at=corner.start();at<corner.end();at+=.2f) {
                            path.pointAt(at,path.laneOffsetAt(at),point);
                            double distance=Double.POSITIVE_INFINITY,maxWidth=0;
                            for(int leg=0;leg<original.points()-1;leg++) {
                                distance=Math.min(distance,segmentDistance(new V(point[0],point[1]),
                                        new V(original.x(leg),original.y(leg)),new V(original.x(leg+1),original.y(leg+1))));
                                maxWidth=Math.max(maxWidth,original.width(leg));
                            }
                            require(distance<=maxWidth/2+1.01,"measured fixture V1 corridor");
                        }
                    }
                }
                ObstacleResult result=obstacleDrive(path,vehicle,new World());
                System.out.println("TURN_FIXTURE "+row[0]+" reverse="+reverse+" corners="+path.corners()
                        +" sharp="+path.cornersSharp()+" "+result);
                require(result.mode==SCRoadFollower.Mode.ARRIVED,"map fixture arrives: "+row[0]+" reverse="+reverse);
            }
        }
        SCDrivePath grouped=SCDrivePath.parse("100,200,8;200,200,8;202,202,8;202,300,8").withCorners(vehicle.profile);
        require(grouped.corners()==1&&grouped.corner(0).arc()
                &&Math.abs(grouped.corner(0).angle()-Math.PI/2)<.001,"two adjacent same-side bends group into a checked arc");
        for(String route:new String[]{"100,200,8;200,200,8;200,208,8;270,208,8",
                "100,200,8;200,200,8;200,270,8;100,270,8"}) {
            SCDrivePath path=SCDrivePath.parse(route).withCorners(vehicle.profile);
            require(path.corners()==2,"opposing dogleg and separated block corners keep distinct IDs");
            require(path.corner(0).end()<=path.corner(1).start(),"adjacent arcs do not overlap");
            require(obstacleDrive(path,vehicle,new World()).mode==SCRoadFollower.Mode.ARRIVED,"multi-corner route arrives");
        }
    }

    /** Largest sideways step of the lane line, ignoring deliberate sharp corners. */
    private static double laneJump(SCDrivePath path) {
        float[] a = new float[5], b = new float[5];
        double worst = 0;
        for (int step = 0; (step + 1) * .02f <= path.length(); step++) {
            float s = step * .02f;
            boolean sharp = false;
            for (int i = 0; i < path.corners(); i++) {
                SCDrivePath.Corner corner = path.corner(i);
                if (!corner.arc() && s > corner.start() - .05f && s < corner.end() + .05f) sharp = true;
            }
            if (sharp) continue;
            path.pointAt(s, path.laneOffsetAt(s), a);
            path.pointAt(s + .02f, path.laneOffsetAt(s + .02f), b);
            worst = Math.max(worst, Math.hypot(b[0] - a[0], b[1] - a[1]) - .02);
        }
        return worst;
    }

    private static float laneNear(SCDrivePath path, float x, float y) {
        SCDrivePath.Projection projection = new SCDrivePath.Projection();
        path.project(x, y, -1, projection);
        return path.laneOffsetAt(projection.along);
    }

    /** Native-model drive along any route: x, y, heading and steering per frame. */
    private static java.util.List<double[]> trace(SCDrivePath path, Vehicle vehicle, V start, double heading, String name) {
        SCRoadFollower follower = new SCRoadFollower(path, 30, true, false, 1);
        Car car = new Car(start, heading, vehicle, true);
        World world = new World();
        SCRoadFollower.Command command = new SCRoadFollower.Command();
        java.util.List<double[]> frames = new java.util.ArrayList<>();
        long now = 0;
        for (int frame = 0; frame < 6000 && follower.mode() != SCRoadFollower.Mode.ARRIVED; frame++) {
            follower.update(world, (float) car.x, (float) car.y, 0, (float) Math.cos(car.heading),
                    (float) Math.sin(car.heading), (float) (car.speed * 3.6), vehicle.profile.halfWidth(),
                    vehicle.profile.halfLength(), -1, -1, now, command);
            frames.add(new double[] {car.x, car.y, car.heading, command.steering});
            car.step(controls(car, command, -1, -1), 1.0 / 30);
            now += 33;
        }
        require(follower.mode() == SCRoadFollower.Mode.ARRIVED, "multi-corner route arrives: " + name + " " + follower.mode());
        return frames;
    }

    /**
     * Router-shaped routes with more than one corner. Every route point carries
     * the width of the street it was reached on, so the point before a junction
     * is often the previous junction or a narrow Lua driveway point.
     */
    private static void multiCorner() {
        Vehicle sedan = VEHICLES[0];
        for (float[] w : new float[][] {{12, 6, 8}, {8, 6, 8}, {6, 8, 8}, {8, 5, 8}}) {
            // East on A, right onto B at (200,200), left onto C at (200,230).
            String text = String.format(Locale.ROOT, "100,200,%.1f;200,200,%.1f;200,230,%.1f;300,230,%.1f",
                    w[0], w[0], w[1], w[2]);
            String name = "w=" + w[0] + ">" + w[1] + ">" + w[2];
            for (boolean reversed : new boolean[] {false, true}) {
                SCDrivePath raw = SCDrivePath.parse(text);
                SCDrivePath path = (reversed ? raw.reversed() : raw).withCorners(sedan.profile);
                String label = name + (reversed ? " reversed" : "");
                require(path.corners() == 2 && path.cornersSharp() == 0, "two checked arcs: " + label);
                require(laneJump(path) < .05, "multi-corner lane continuity " + label + " jump=" + laneJump(path));
                require(Math.abs(laneNear(path, 200, 215) - lane(w[1])) < .01,
                        "the street between two turns keeps its own lane: " + label + " lane=" + laneNear(path, 200, 215));
                // An obstacle can leave the first turn sharp. Its junction point
                // then stays in the route, still carrying the previous street.
                SCDrivePath sharpFirst = path.sharpCorner(0);
                require(!sharpFirst.corner(0).arc() && sharpFirst.corner(1).arc(), "first turn sharp, second an arc: " + label);
                require(laneJump(sharpFirst) < .05, "an arc after a sharp turn meets its straight " + label
                        + " jump=" + laneJump(sharpFirst));
                require(Math.abs(laneNear(sharpFirst, 200, 215) - lane(w[1])) < .01,
                        "the street after a sharp turn keeps its own lane: " + label + " lane=" + laneNear(sharpFirst, 200, 215));
            }
            if (w[0] == 12 && w[1] == 6) {
                SCDrivePath path = SCDrivePath.parse(text).withCorners(sedan.profile);
                double worst = 0;
                for (double[] f : trace(path, sedan, new V(104, 200 + lane(w[0])), 0, name)) {
                    if (f[1] > 208 && f[1] < 222 && Math.abs(SCTurnAround.wrap((float) (f[2] - Math.PI / 2))) < .2)
                        worst = Math.max(worst, Math.abs(f[0] - (200 - lane(w[1]))));
                }
                require(worst <= .6, "the car holds the narrow street's lane between two turns: " + worst);
            }
        }
        // Lua narrows both driveway ends to width 5; the street reached at the
        // entry point is 8 wide. The first junction must start from that lane.
        SCDrivePath driveway = SCDrivePath.parse("200,185,5;200,200,5;230,200,8;230,260,8").withCorners(sedan.profile);
        require(driveway.corners() == 2 && driveway.cornersSharp() == 0, "driveway exit and first junction are arcs");
        require(laneJump(driveway) < .05, "driveway route lane continuity jump=" + laneJump(driveway));
        require(Math.abs(driveway.laneOffsetAt(driveway.corner(1).start()) - 2) < .01,
                "the first junction after a driveway starts from the street's lane: "
                        + driveway.laneOffsetAt(driveway.corner(1).start()));
        double closest = Double.POSITIVE_INFINITY, steer = 0;
        for (double[] f : trace(driveway, sedan, new V(200, 187), Math.PI / 2, "driveway")) {
            if (f[0] > 212 && f[0] < 229 && f[1] < 204) closest = Math.min(closest, f[1] - 200);
            if (f[0] > 218 && f[0] < 232 && f[1] < 206) steer = Math.max(steer, Math.abs(f[3]));
        }
        require(closest >= 1.5 && steer <= .7, "no swing to the centre before the first right turn: right of centre="
                + closest + " steering=" + steer);
        // Lua's road exit: the street's own width 4 m before the narrowed exit point.
        SCDrivePath exit = SCDrivePath.parse("170,200,12;200,200,12;200,226,8;200,230,5;208,230,5")
                .withCorners(sedan.profile);
        require(exit.corner(0).arc() && Math.abs(exit.laneOffsetAt(exit.corner(0).end()) - 2) < .01,
                "the last street before a road exit keeps its lane: " + exit.laneOffsetAt(exit.corner(0).end()));
        require(laneJump(exit) < .05, "road-exit route lane continuity jump=" + laneJump(exit));
        System.out.println("TURN_MULTI_CORNER_PASS");
    }

    public static void main(String[] args) throws java.io.IOException, ReflectiveOperationException {
        String check=System.getProperty("turnCheck","all");
        // Cargo, Release and the dedicated script enforce the full budget.
        // Functional-only mode remains an explicit diagnostic.
        boolean suite=check.equals("all")||check.equals("functional");
        if(suite||check.equals("geometry")) geometry();
        if(suite||check.equals("sides")) sideFixture();
        if(suite||check.equals("hold")) sharpHold();
        if(suite||check.equals("governor")) speedGovernor();
        if(suite||check.equals("approach")) approachTiming();
        if(suite||check.equals("bumper")) bumperCorner();
        if(suite||check.equals("clearBumper")) clearBumperLookAhead();
        if(suite||check.equals("cornerRecovery")) cornerBumperRecovery();
        if(suite||check.equals("rosewood")) rosewoodCornerRecovery();
        if(suite||check.equals("shortScan")) shortScan();
        if(suite||check.equals("filledStrip")) filledStrip();
        if(suite||check.equals("lateOffset")) lateOffsetBodySweep();
        if(suite||check.equals("reverse")) reverse();
        if(suite||check.equals("multiCorner")) multiCorner();
        if(check.equals("right")) laneContract(true);
        if(check.equals("left")) laneContract(false);
        if(check.equals("speed")) speedContract();
        if(suite||check.equals("merge")) merging();
        if(suite||check.equals("fixtures")) fixtures();
        if(suite||check.equals("obstacles")||check.equals("wreck")||check.equals("lamp")
                ||check.equals("blocked")||check.equals("walls")||check.equals("cost")) obstacles(suite?"obstacles":check);
        if(suite||check.equals("matrix")) {
            smokeMatrix();
            if (!Boolean.getBoolean("turnSmoke")) matrix(!check.equals("functional"));
        }
        require(checks>0,"unknown or empty turn check: "+check);
        System.out.println((check.equals("functional")?"INTERSECTION_FUNCTIONAL_PASS":"INTERSECTION_TURNS_PASS")+" checks="+checks);
    }
}
