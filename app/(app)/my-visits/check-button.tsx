"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";

import { checkIn, checkOut } from "./actions";

function currentPosition(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!("geolocation" in navigator)) {
      reject(new Error("This browser can't share its location."));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 15000,
      maximumAge: 0,
    });
  });
}

function locationErrorMessage(error: unknown): string {
  if (error instanceof GeolocationPositionError) {
    if (error.code === error.PERMISSION_DENIED) return "Location access is blocked. Allow it in your browser settings and try again.";
    if (error.code === error.TIMEOUT) return "Finding your location took too long. Move somewhere with better signal and try again.";
    return "Your location couldn't be found. Try again.";
  }
  return error instanceof Error ? error.message : "Your location couldn't be found. Try again.";
}

export function CheckButton({ visitId, kind }: { visitId: string; kind: "in" | "out" }) {
  const [locating, setLocating] = useState(false);
  const [pending, startTransition] = useTransition();
  const busy = locating || pending;

  async function handleClick() {
    setLocating(true);
    let position: GeolocationPosition;
    try {
      position = await currentPosition();
    } catch (error) {
      toast.error(locationErrorMessage(error));
      return;
    } finally {
      setLocating(false);
    }

    const input = { visitId, latitude: position.coords.latitude, longitude: position.coords.longitude };
    startTransition(async () => {
      const result = kind === "in" ? await checkIn(input) : await checkOut(input);
      if (result.ok) toast.success(result.message);
      else toast.error(result.error);
    });
  }

  return (
    <Button className="w-full" size="lg" variant={kind === "in" ? "default" : "secondary"} disabled={busy} onClick={handleClick}>
      {locating ? "Finding your location…" : pending ? "Saving…" : kind === "in" ? "Check in" : "Check out"}
    </Button>
  );
}
